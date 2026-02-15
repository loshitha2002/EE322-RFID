## Detailed Code Explanation — `TwoFactorLock_Full.S`

### 1. Preprocessor & Constants (Lines 1–93)

```asm
#define __SFR_OFFSET 0
#include <avr/io.h>
```

- **`__SFR_OFFSET 0`** — Forces all I/O register addresses to use the **memory-mapped** address (not the I/O-mapped address), so `sts`/`lds` instructions work correctly.
- **`<avr/io.h>`** — Includes ATmega328P register definitions (`PORTB`, `DDRB`, `SPCR`, `SPDR`, etc.).

#### Constants Block (Lines 36–92)

| Constant | Value | Purpose |
|---|---|---|
| `PIN_LENGTH` | 4 | Number of digits in the secret PIN |
| `MAX_ATTEMPTS` | 3 | Wrong attempts before lockout |
| `LOCKOUT_TIME_S` | 30 | Lockout duration in seconds |
| `SYS_IDLE` to `SYS_LOCKOUT` | 0–5 | State machine state IDs |
| `LCD_ADDR` | `0x27` | I2C slave address of the PCF8574 LCD backpack |
| `LCD_BACKLIGHT`, `LCD_ENABLE`, `LCD_RS` | `0x08`, `0x04`, `0x01` | Control bits sent over I2C to the LCD module |
| `SPI_SS` to `SPI_SCK` | PB2–PB5 | SPI bus pin assignments |
| `MFRC_*` | Various | MFRC522 register addresses |
| `CMD_*`, `PICC_*` | Various | MFRC522 command and PICC command constants |
| `TWBR_REG` to `TWCR_REG` | `0xB8`–`0xBC` | ATmega328P TWI (I2C) hardware registers |
| `TWINT_BIT` to `TWEN_BIT` | 7, 6, 5, 4, 2 | TWI control register bit positions |

---

### 2. Data Section (Lines 94–178)

```asm
.section .data
```

This section reserves space in **SRAM** for variables and lookup tables.

| Variable | Size | Purpose |
|---|---|---|
| `secret_pin` | 5 bytes | Stores the secret PIN `"1234"` + null terminator |
| `secret_uid` | 4 bytes | Stores the RFID UID `{0x67, 0x93, 0xA9, 0x04}` |
| `input_buffer` | 5 bytes | Buffer where the user-entered digits are stored |
| `current_state` | 1 byte | Current FSM state |
| `input_index` | 1 byte | Number of digits entered so far |
| `wrong_attempts` | 1 byte | Counter of consecutive wrong PIN attempts |
| `is_locked_out` | 1 byte | Boolean flag: `1` if in lockout |
| `lockout_counter` | 1 byte | Counts down from 30 to 0 during lockout |
| `scanned_uid` | 4 bytes | Buffer for the UID read from the RFID card |
| `keypad_map` | 16 bytes | 4×4 lookup table mapping (row, col) → ASCII character |

**String constants** (`str_booting`, `str_ready`, `str_enter_pin`, etc.) match the LCD messages exactly as in the original `.ino` sketch.

---

### 3. Interrupt Vector Table (Lines 180–218)

```asm
.section .text
.org 0x0000
    rjmp    RESET               ; Vector 0: Reset
    rjmp    DEFAULT_HANDLER     ; Vector 1: INT0
    ...
    rjmp    TIMER0_OVF_ISR      ; Vector 7: Timer0 Overflow
    ...
DEFAULT_HANDLER:
    reti
```

- **Line 186:** On power-on/reset, jump to `RESET`.
- **Line 193:** Timer0 overflow — jumps to `TIMER0_OVF_ISR` (used for approximate millisecond timing).
- All other interrupts jump to `DEFAULT_HANDLER` which just returns (`reti`).

**Timer0 ISR (Lines 206–218):** Saves `SREG` and `r16` on the stack, then restores them before `reti`. The ISR body is a stub (placeholder for future lockout timing).

---

### 4. RESET / Setup (Lines 220–343)

This is the **setup** routine, equivalent to `void setup()` in the Arduino sketch.

#### Stack Pointer Init (Lines 225–229)
```asm
ldi r16, hi8(RAMEND)
out SPH, r16
ldi r16, lo8(RAMEND)
out SPL, r16
```
Sets the stack pointer to the top of SRAM (`RAMEND = 0x08FF` for ATmega328P).

#### Pin Configuration (Lines 231–261)
- **Outputs:** Buzzer (PB0), Lock relay (PD7), LED (PC3) — set via `sbi DDRx, pin`.
- **All outputs LOW initially** — `cbi PORTx, pin`.
- **Keypad rows (PD2–PD5):** Configured as outputs (active-LOW scanning).
- **Keypad columns (PD6, PC0–PC2):** Configured as inputs with internal pull-ups enabled.

#### SPI Init (Lines 263–280)
- MOSI, SCK, SS, RST → output; MISO → input.
- SS HIGH (deselect RFID chip).
- RST HIGH (RFID not in reset).
- **SPCR register:** SPI enabled, master mode, clock = `fck/16` (1 MHz SPI clock).

#### I2C & LCD Init (Lines 282–307)
- Calls `i2c_init` — sets TWI bit rate to 100 kHz.
- Calls `lcd_init` — sends the HD44780 4-bit initialization sequence over I2C.
- Turns on backlight, clears the display.
- Displays `"System Booting"` and waits 1 second.

#### RFID Init (Lines 309–315)
- Calls `mfrc522_init` — performs a hardware + software reset, configures timers, enables antenna.
- Waits 1.5 seconds for the module to stabilize.

#### State Variable Init (Lines 317–343)
- `current_state = SYS_IDLE`
- `wrong_attempts = 0`, `is_locked_out = 0`, `input_index = 0`
- Clears `input_buffer` (5 bytes).
- Calls `reset_system` to display `"READY. Press Key"`.
- **`sei`** — enables global interrupts.

---

### 5. Main Loop & State Machine (Lines 345–383)

```asm
main_loop:
    lds  r16, current_state
    cpi  r16, SYS_IDLE          ; → state_idle
    cpi  r16, SYS_ENTER_PIN     ; → state_enter_pin
    cpi  r16, SYS_CHECK_PIN     ; → state_check_pin
    cpi  r16, SYS_WAIT_RFID     ; → state_wait_rfid
    cpi  r16, SYS_ACCESS_GRANTED; → state_access_granted
    cpi  r16, SYS_LOCKOUT       ; → state_lockout
    rjmp main_loop              ; Default: loop again
```

- Reads `current_state` from SRAM and branches to the corresponding state handler.
- **Jump trampolines** (Lines 373–383) are needed because `breq` has a limited range (±64 words). The trampolines use `rjmp` which has a longer range.

---

### 6. State: SYS_IDLE (Lines 385–461)

**Purpose:** Wait for any keypress to begin PIN entry.

1. **Scan keypad** — calls `scan_keypad`, result in `r24`.
2. If no key pressed (`r24 == 0`), jump back to `main_loop`.
3. If a key is pressed:
   - Clear LCD, print `"Enter PIN:"`, move cursor to row 1.
   - Transition to `SYS_ENTER_PIN`.
   - If the key is a digit (`≠ '#'` and `≠ '*'`): store it in `input_buffer`, increment `input_index`, display `'*'` on LCD, and beep.
   - If `'*'` is pressed: call `reset_system` (go back to READY screen).
   - If `'#'` is pressed: ignore (no digits entered yet).

---

### 7. State: SYS_ENTER_PIN (Lines 463–531)

**Purpose:** Collect up to 4 PIN digits from the keypad.

1. **Scan keypad** — if no key, return to `main_loop`.
2. **Any key press triggers a short beep.**
3. **`'#'` key** → transition to `SYS_CHECK_PIN` (submit the PIN).
4. **`'*'` key** → call `reset_system` (cancel and return to IDLE).
5. **Digit key (0–9, A–D):**
   - If `input_index < 4`: store the digit, increment index, null-terminate buffer, print `'*'` on LCD.
   - If buffer is full: ignore the keypress.

---

### 8. State: SYS_CHECK_PIN (Lines 533–683)

**Purpose:** Verify the entered PIN against the stored secret.

1. Display `"Verifying..."` and wait 750 ms.
2. **Byte-by-byte comparison** (Lines 550–578):
   - Loads `input_buffer` into X register and `secret_pin` into Z register.
   - Compares 4 bytes. If any mismatch, sets `r18 = 1`.
   - Also checks that `input_buffer[4]` is null (no extra characters).
3. **PIN Correct** (Lines 584–614):
   - Resets `wrong_attempts` to 0.
   - Displays `"PIN OK!"` and `"Scan Card"`.
   - Confirmation beep.
   - Transitions to `SYS_WAIT_RFID`.
4. **PIN Wrong** (Lines 616–683):
   - Increments `wrong_attempts`.
   - Displays `"Wrong PIN!"`.
   - If `wrong_attempts >= 3`: displays `"SYSTEM LOCKED!"`, sounds alarm, calls `start_lockout`.
   - Otherwise: displays remaining tries (e.g., `"Tries left: 2"`), error beep, waits 2 s, calls `reset_system`.

---

### 9. State: SYS_WAIT_RFID (Lines 685–764)

**Purpose:** Wait for an RFID card and verify its UID.

1. **Detect card** — calls `mfrc522_request`. If no card found, return to `main_loop`.
2. **Read UID** — calls `mfrc522_anticoll`. UID is stored in `scanned_uid`.
3. Displays `"Reading Card..."`.
4. **Compare UID** — compares 4 bytes of `scanned_uid` with `secret_uid`.
5. **Match** → transition to `SYS_ACCESS_GRANTED`.
6. **No match** → displays `"Unknown Card!"`, error beep, waits 2 s, calls `reset_system`.
7. Calls `mfrc522_halt` to put the card to sleep.

---

### 10. State: SYS_ACCESS_GRANTED (Lines 766–806)

**Purpose:** Both factors verified — unlock the door.

1. Displays `"ACCESS GRANTED"`.
2. **Lock relay ON** (`sbi PORTD, PD7`), **LED ON** (`sbi PORTC, PC3`).
3. Success beep.
4. **Wait 3 seconds** (door remains unlocked).
5. **Lock relay OFF**, **LED OFF**.
6. Reset `wrong_attempts` to 0.
7. Call `reset_system` → back to `SYS_IDLE`.

---

### 11. State: SYS_LOCKOUT (Lines 808–888)

**Purpose:** Enforce a 30-second penalty after 3 wrong PINs.

1. Displays `"!! LOCKED OUT !!"` on row 0.
2. Displays `"Wait: XXs"` on row 1 (countdown).
3. Short alarm beep every second.
4. **Reads and discards** keypad input (no entry allowed).
5. **Decrements `lockout_counter`** each second.
6. When counter reaches 0:
   - Clears `is_locked_out` and `wrong_attempts`.
   - Displays `"Lock Released"`, confirmation beep.
   - Waits 1.5 s, then calls `reset_system`.

---

### 12. Helper: start_lockout (Lines 890–907)

Sets `is_locked_out = 1`, `lockout_counter = 30`, and `current_state = SYS_LOCKOUT`.

---

### 13. Helper: reset_system (Lines 909–973)

Resets the system to the IDLE state:
- Clears LCD, prints `"READY. Press Key"`.
- If there are prior wrong attempts, shows `"Tries: X left"` on row 1.
- Sets `current_state = SYS_IDLE`, `input_index = 0`.
- Clears `input_buffer`.
- Turns **lock** and **LED** off.

---

### 14. Keypad Scanner (Lines 975–1111)

**Algorithm:** Row-scanning with active-LOW outputs and pull-up inputs.

1. Set all 4 rows HIGH.
2. For each row (0–3):
   - Drive that row LOW.
   - Wait 6 NOPs (~375 ns at 16 MHz) for the signal to settle.
   - Check each column pin (PD6, PC0, PC1, PC2) — if LOW, a key is pressed.
3. If a key is found:
   - Calculate index: `row × 4 + col`.
   - Look up ASCII character from `keypad_map`.
   - **Debounce:** wait (polling every 10 ms) until the key is released.
4. Restore all rows HIGH; return the ASCII character in `r24` (or `0` if none).

---

### 15. I2C (TWI) Driver (Lines 1113–1154)

Low-level I2C functions using the ATmega328P's built-in TWI hardware:

| Function | Purpose |
|---|---|
| `i2c_init` | Set SCL frequency to 100 kHz (`TWBR = 72`, prescaler = 1) |
| `i2c_start` | Send I2C START condition and wait for `TWINT` flag |
| `i2c_stop` | Send I2C STOP condition |
| `i2c_write` | Write a byte (in `r24`) and wait for completion |

---

### 16. LCD I2C Driver (Lines 1156–1361)

Drives an HD44780 LCD through a PCF8574 I2C expander in **4-bit mode**.

| Function | Purpose |
|---|---|
| `lcd_init` | Sends the power-on initialization sequence (three `0x30` nibbles, then `0x20` to enter 4-bit mode), configures 2-line display, cursor off |
| `lcd_clear` | Sends clear-display command (`0x01`) + 5 ms delay |
| `lcd_set_cursor` | Sets DDRAM address — row 0 offset = `0x00`, row 1 offset = `0x40` |
| `lcd_print_char` | Sends a single data byte (with RS=1) |
| `lcd_print_string` | Iterates through a null-terminated string in SRAM via Z pointer |
| `lcd_print_number` | Prints an integer (0–99) as decimal ASCII |
| `lcd_send_command` | Sends a command byte as two 4-bit nibbles with RS=0 |
| `lcd_send_data` | Sends a data byte as two 4-bit nibbles with RS=1 |
| `lcd_write_nibble_en` | Sends a nibble with an ENABLE pulse (EN HIGH → delay → EN LOW) |
| `lcd_i2c_write_byte` | Sends a full I2C transaction: START → address (0x4E) → data → STOP |

---

### 17. SPI Driver (Lines 1363–1401)

| Function | Purpose |
|---|---|
| `spi_transfer` | Writes `r24` to `SPDR`, waits for `SPIF`, reads result into `r24` |
| `mfrc522_write_reg` | Writes value `r25` to MFRC522 register `r24`. Address format: `(reg << 1) & 0x7E` + SS LOW/HIGH framing |
| `mfrc522_read_reg` | Reads MFRC522 register `r24`. Address format: `((reg << 1) & 0x7E) | 0x80` (read bit set) |

---

### 18. MFRC522 RFID Driver (Lines 1403–1625)

| Function | Purpose |
|---|---|
| `mfrc522_init` | Hardware reset (RST LOW→HIGH), soft reset, configure timer registers, set 100% ASK modulation, turn on antenna |
| `mfrc522_request` | Sends REQA (`0x26`) via Transceive command; returns `r24 = 0` if a card responds, `1` on timeout |
| `mfrc522_anticoll` | Sends anti-collision command (`0x93, 0x20`); reads 4-byte UID from FIFO into `scanned_uid`; returns `r24 = 0` on success |
| `mfrc522_halt` | Sends HLTA (`0x50, 0x00`) to put the card to sleep |

Each function follows the pattern: write to FIFO → execute command → start transmission → poll `ComIrqReg` with timeout.

---

### 19. Buzzer Functions (Lines 1627–1674)

Simple ON/OFF patterns using `sbi`/`cbi` on PB0:

| Function | Duration | Use Case |
|---|---|---|
| `buzzer_short_beep` | 50 ms | Key press feedback |
| `buzzer_confirm_beep` | 150 ms | PIN correct confirmation |
| `buzzer_error_beep` | 750 ms | Wrong PIN / unknown card |
| `buzzer_success_beep` | 250 ms | Access granted |
| `buzzer_alarm` | 2000 ms | System locked alarm |
| `buzzer_alarm_short` | 200 ms | Lockout countdown tick |

---

### 20. Delay Functions (Lines 1676–1733)

Built from a base nested loop (`delay_1ms`) at 16 MHz clock frequency, then composed:

```
delay_1ms → delay_5ms → delay_10ms → delay_50ms → delay_100ms → delay_250ms → delay_500ms → delay_1000ms
```

The base `delay_1ms` uses a two-register nested decrement loop (`r16` outer × `r17` inner) calibrated for approximately 1 ms at 16 MHz.

---