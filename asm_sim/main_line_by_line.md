# Line‑by‑line explanation of asm_sim/main.S

This document explains each line/section of the AVR assembly file used for the ATmega328P simulation. It follows the original order and describes what each instruction or block does and why it exists.

> File: asm_sim/main.S

---

## Header & configuration
- `// ATmega328P - Assembly simulation (Stable UART Version)`
  - Comment: indicates target MCU and that this is a UART‑stable simulation build.
- `// Uses Double Speed (U2X) for maximum baud rate accuracy`
  - Comment: explains UART is configured in double‑speed mode for better baud accuracy.
- `// UART: 9600 Baud`
  - Comment: sets intended baud rate.
- `// F_CPU: 16MHz (Make sure Proteus matches this!)`
  - Comment: indicates CPU clock for simulation must match 16 MHz.

- `#ifndef F_CPU`
  - Preprocessor guard: if `F_CPU` not defined externally, define it here.
- `#define F_CPU 16000000UL`
  - Defines CPU clock used for baud calculation.
- `#endif`
  - Ends guard.

### UART constants
- `#define BAUD 9600UL`
  - Desired baud rate.
- `#define UBRR_VAL (((F_CPU + (BAUD*4UL)) / (8UL*BAUD)) - 1UL)`
  - Computes UBRR value for double‑speed mode ($U2X=1$). Uses rounding for accuracy.

### I/O register addresses
Each `#define` gives the I/O register address for direct `lds/sts` or `in/out` use.
- `#define DDRB 0x24`, `PORTB 0x25`
  - Data direction and output registers for port B.
- `#define DDRD 0x2A`, `PORTD 0x2B`
  - Data direction and output registers for port D.
- `#define EICRA 0x69`, `EIMSK 0x3D`
  - External interrupt control register A and mask register.
- `#define TCCR1A 0x80`, `TCCR1B 0x81`
  - Timer1 control registers.
- `#define OCR1AL 0x88`, `OCR1AH 0x89`
  - Timer1 compare A registers.
- `#define TIMSK1 0x6F`
  - Timer1 interrupt mask.
- `#define UCSR0A 0xC0`, `UCSR0B 0xC1`, `UCSR0C 0xC2`
  - UART control and status registers.
- `#define UBRR0L 0xC4`, `UBRR0H 0xC5`
  - UART baud rate registers.
- `#define UDR0 0xC6`
  - UART data register.
- `#define EECR 0x3F`, `EEDR 0x40`, `EEARL 0x41`, `EEARH 0x42`
  - EEPROM control, data, and address registers.

### Bit definitions
- `#define RXC0 7` — UART receive complete bit.
- `#define UDRE0 5` — UART data register empty bit.
- `#define U2X0 1` — UART double speed bit.
- `#define RXEN0 4`, `TXEN0 3` — UART receiver/transmitter enable.
- `#define UCSZ00 1`, `UCSZ01 2` — UART data size bits (8‑bit data).

---

## SRAM variables (.bss)
These are zero‑initialized RAM variables.
- `.section .bss` — switch to BSS section.
- `.global wrong_attempts` — export symbol.
- `wrong_attempts: .skip 1` — 1 byte counter for wrong tags.
- `.global lockout_sec`
- `lockout_sec: .skip 1` — remaining lockout seconds.
- `.global lock_state`
- `lock_state: .skip 1` — lock state: 0=locked, 1=unlocked.
- `.global save_req`
- `save_req: .skip 1` — flag set by INT0 to request EEPROM save.
- `.global tick_flag`
- `tick_flag: .skip 1` — flag set by Timer1 ISR every second.

---

## Register usage and memory allocation (detailed)

### 1) CPU register allocation (general purpose)
The code does not use a formal ABI, but there is a clear pattern of register roles:

- `r16` — **primary scratch/parameter register** used almost everywhere:
  - UART TX character payload (`UART_TX` reads it, many callers write into it).
  - GPIO/bit manipulation temporary value (`APPLY_LOCK_`, GPIO init).
  - EEPROM read/write data (read returns in `r16`; write data loaded into `r16`).
  - Message printing loop (`PRINT_Z` loads bytes into `r16`).

- `r17` — **secondary scratch / EEPROM address / lockout counter**:
  - EEPROM byte address passed in `r17` for `EEPROM_READ_BYTE/EEPROM_WRITE_BYTE`.
  - Used in Timer ISR for `lockout_sec` decrement.

- `r18` — **UART status and EEPROM control temp**:
  - Polls `UCSR0A` in `UART_RX_POLL` and `UART_TX`.
  - Temporary when toggling EEPROM control bits in EEPROM helpers.

- `r19` — **delay / timing loop counter**:
  - Used in `BEEP_SHORT` and `DELAY_VISIBLE`.

- `r20`, `r21` — **inner delay counters**:
  - Used in UART TX delay and `DELAY_SHORT`.

- `r22` — **startup blink counter**:
  - Used in `STARTUP_BLINK`.

**Important note on clobbering:**
There is no formal call‑saved vs call‑clobbered discipline. Routines that need to preserve registers explicitly `push`/`pop` them (see `BEEP_SHORT` and ISRs). That’s why `DO_WRONG` reloads `wrong_attempts` after calling `PRINT_WRONG`, because printing clobbers `r16`.

### 2) Stack usage and allocation
- Stack is manually set to `0x08FF` (RAM end for ATmega328P with 2 KB SRAM).
  - `SPH` is at I/O address `0x3E` and `SPL` at `0x3D`.
  - Stack grows **downward** from `0x08FF` toward lower SRAM.

**Where the stack is used:**
- Function calls (`rcall`) push the return address.
- ISRs push registers they modify (`r16`, `r17`) and also save `SREG`.
- `BEEP_SHORT` pushes `r16`, `r19`, `r20`, `r21` to preserve caller state.

There is **no explicit stack frame** or local variables; stack usage is only for return addresses and saved registers.

### 3) SRAM allocation (data memory)
The `.bss` variables are placed by the linker in SRAM after any `.data` section.
These symbols are 1 byte each:

- `wrong_attempts` — counter incremented on wrong attempts.
- `lockout_sec` — countdown in seconds.
- `lock_state` — 0/1 lock LED state.
- `save_req` — request flag set by INT0 ISR.
- `tick_flag` — heartbeat flag set by Timer1 ISR.

Because each is `.skip 1`, they are contiguous and minimal RAM is used. The exact addresses are resolved by the linker but remain in SRAM (not I/O or EEPROM).

### 4) EEPROM allocation (non‑volatile)
The EEPROM layout is fixed by the code:

- Address `0`: **signature byte** `0xA5`.
- Address `1`: `lock_state`.
- Address `2`: `wrong_attempts`.
- Address `3`: `lockout_sec`.

This layout is enforced in `EEPROM_LOAD` and `EEPROM_SAVE`:
- `EEPROM_LOAD` checks signature at `0` before using data.
- `EEPROM_SAVE` always writes signature first, then state bytes.

### 5) Program memory allocation
Constant strings are stored in **flash** (`.text`) and accessed by `LPM` through the Z pointer:

- `msg_banner`, `msg_ok`, `msg_wrong`, `msg_lockout`, `msg_saved`.

`PRINT_Z` uses `LPM r16, Z+` to read flash bytes sequentially until a NUL terminator.

### 6) I/O space vs memory space
The file mixes `out/in` and `sts/lds` to access registers:

- `out`/`in` are used for **low I/O addresses** (e.g., stack pointer at `0x3D/0x3E`).
- `lds`/`sts` are used for **extended I/O / memory‑mapped registers** like `UCSR0A` (0xC0), `TCCR1B` (0x81), etc.

### 7) Status register (SREG) handling
Both ISRs save and restore `SREG` using:
- `in r16, 0x3F` to read SREG
- push/pop around the ISR work
- `out 0x3F, r16` to restore

This preserves the global interrupt flag and status bits for mainline code.

### 8) Z pointer usage
The Z pointer (`r31:r30`) is used only for program memory string printing.

- `PRINT_BANNER` etc. load Z with `msg_*` address.
- `PRINT_Z` consumes Z until NUL.

No other pointer registers (X/Y) are used in this file.

---

## Code section & reset entry
- `.section .text` — code section.
- `.global main` — export `main` label as entry.
- `main:` — reset entry label.

### 1) Stack initialization
- `ldi r16, hi8(0x08FF)`
  - Load high byte of RAM end into `r16`.
- `out 0x3E, r16`
  - Write high byte to SPH (stack pointer high).
- `ldi r16, lo8(0x08FF)`
  - Load low byte of RAM end.
- `out 0x3D, r16`
  - Write low byte to SPL (stack pointer low).

### 2) GPIO setup
**PD7 as LED output**
- `lds r16, DDRD`
  - Read DDRD.
- `ori r16, (1<<7)`
  - Set bit 7 → PD7 output.
- `sts DDRD, r16`
  - Write DDRD back.

**PB0 as buzzer output**
- `lds r16, DDRB`
- `ori r16, (1<<0)`
  - Set PB0 output.
- `sts DDRB, r16`

**PD2 as input with pull‑up (INT0 button)**
- `lds r16, DDRD`
- `andi r16, ~(1<<2)`
  - Clear bit 2 → input.
- `sts DDRD, r16`
- `lds r16, PORTD`
- `ori r16, (1<<2)`
  - Enable pull‑up on PD2.
- `sts PORTD, r16`

### 3) UART setup (double speed)
- `ldi r16, (1<<U2X0)`
  - Enable U2X (double speed) in UCSR0A.
- `sts UCSR0A, r16`

- `ldi r16, 0`
- `sts UBRR0H, r16`
  - Clear high byte of UBRR.
- `ldi r16, lo8(UBRR_VAL)`
- `sts UBRR0L, r16`
  - Set baud rate.

- `ldi r16, (1<<RXEN0)|(1<<TXEN0)`
  - Enable RX and TX.
- `sts UCSR0B, r16`
- `ldi r16, (1<<UCSZ01)|(1<<UCSZ00)`
  - 8‑bit data, 1 stop bit, no parity (8N1).
- `sts UCSR0C, r16`

### 4) Timer1 setup (1s tick)
- `ldi r16, 0`
- `sts TCCR1A, r16`
  - Normal port operation.
- `ldi r16, (1<<3)|(1<<2)|(1<<0)`
  - WGM12=1 (CTC), prescaler /1024 (CS12+CS10).
- `sts TCCR1B, r16`

- `ldi r16, hi8(15624)`
- `sts OCR1AH, r16`
- `ldi r16, lo8(15624)`
- `sts OCR1AL, r16`
  - Compare match at 15624 → ~1s tick at 16 MHz, /1024.

- `ldi r16, (1<<1)`
  - OCIE1A enable.
- `sts TIMSK1, r16`

### 5) External interrupt INT0 on falling edge
- `ldi r16, (1<<1)`
  - ISC01=1, ISC00=0 → falling edge.
- `sts EICRA, r16`
- `ldi r16, (1<<0)`
  - Enable INT0.
- `sts EIMSK, r16`

### 6) Startup state
- `ldi r16, 0`
- `sts wrong_attempts, r16`
- `sts lockout_sec, r16`
- `sts save_req, r16`
- `sts tick_flag, r16`
  - Clear all flags/counters.

- `rcall EEPROM_LOAD`
  - Restore persisted state (if valid).
- `rcall APPLY_LOCK_`
  - Apply `lock_state` to LED output.

- `rcall DELAY_VISIBLE`
  - Small delay so UART/LED is stable.

- `ldi r16, '!'`
- `rcall UART_TX`
  - Sends a marker character to UART.

- `rcall PRINT_BANNER`
  - Prints "READY" banner.

- `rcall STARTUP_BLINK`
  - Blinks LED 3 times.

- `sei`
  - Enable global interrupts.

---

## Main loop
- `MAIN_LOOP:`
  - Start of main loop.

### Heartbeat (1s tick)
- `lds r16, tick_flag`
- `tst r16`
- `breq NO_TICK`
  - If no tick, skip.
- `ldi r16, 0`
- `sts tick_flag, r16`
  - Clear tick flag.
- `ldi r16, '.'`
- `rcall UART_TX`
  - Print heartbeat dot.
- `NO_TICK:`

### Save request
- `lds r16, save_req`
- `tst r16`
- `breq NO_SAVE`
- `ldi r16, 0`
- `sts save_req, r16`
- `rcall EEPROM_SAVE`
- `rcall PRINT_SAVED`
  - If INT0 set save flag, commit to EEPROM and print.
- `NO_SAVE:`

### UART receive and command handling
- `rcall UART_RX_POLL`
- `brtc MAIN_LOOP`
  - If no character, return to loop.

- `rcall UART_TX`
  - Echo received character.

- `cpi r16, 'A'`
- `breq DO_AUTH`
- `cpi r16, 'W'`
- `breq DO_WRONG`
- `cpi r16, 'P'`
- `breq DO_SAVE`
- `rjmp MAIN_LOOP`
  - Dispatch: A=authorized, W=wrong, P=save.

---

## Logic handlers
### DO_AUTH
- Check `lockout_sec`; if non‑zero, ignore.
- Set `lock_state=1`, reset `wrong_attempts`.
- Apply lock, print OK, beep, return.

### DO_WRONG
- Ignore if in lockout.
- Increment `wrong_attempts`.
- Print WRONG, beep.
- If attempts == 3, set `lockout_sec=30`, force locked, apply, print LOCKOUT.

### DO_SAVE
- Force EEPROM save and print SAVED, beep.

---

## UART helpers
### UART_RX_POLL
- Poll RXC0. If no data, clear T flag and return.
- If data, read UDR0 to r16 and set T flag.

### UART_TX
- Wait until UDRE0 set (data register empty).
- Write r16 to UDR0.
- Extra delay loop to avoid Proteus terminal overrun.

---

## Output helpers
### APPLY_LOCK_
- If `lock_state` non‑zero → set PD7 high (LED ON).
- Else clear PD7 (LED OFF).

### PRINT_Z and message functions
- `PRINT_Z` reads program memory at Z and writes each byte until NUL.
- `PRINT_BANNER`, `PRINT_OK`, `PRINT_WRONG`, `PRINT_LOCKOUT`, `PRINT_SAVED` load Z with string label and call `PRINT_Z`.

### STARTUP_BLINK
- Blink LED 3 times with visible delay.

### BEEP_SHORT
- Turn buzzer on PB0, wait ~50ms, turn it off.

### DELAY_SHORT / DELAY_VISIBLE
- Nested software delays for timing.

---

## Interrupt service routines
### INT0 ISR (`__vector_1`)
- Saves registers.
- Sets `save_req=1` so main loop will save EEPROM.
- Restores SREG and returns from interrupt.

### Timer1 Compare A ISR (`__vector_11`)
- Sets `tick_flag=1` every second.
- If in lockout, decrements `lockout_sec` each tick.
- Beeps during lockout.
- When lockout ends, resets `wrong_attempts`.

---

## EEPROM helpers
### EEPROM_READ_BYTE
- Waits for any pending write to finish.
- Loads EEPROM address in `EEAR` (low byte in r17).
- Starts read by setting EERE.
- Returns byte in r16.

### EEPROM_WRITE_BYTE
- Waits for any pending write to finish.
- Loads address and data.
- Sets EEMPE then EEPE to start write.

### EEPROM_LOAD
- Reads byte 0 and checks for signature 0xA5.
- If valid: loads `lock_state` and `wrong_attempts`.
- Clears `lockout_sec` on boot for testing.
- If invalid: clears all state.

### EEPROM_SAVE
- Writes signature 0xA5 at address 0.
- Saves `lock_state`, `wrong_attempts`, `lockout_sec` to addresses 1–3.

---

## Strings
- `.section .text` / `.asciz` strings for UART output.
  - `msg_banner`: "READY\r\n"
  - `msg_ok`: "OK\r\n"
  - `msg_wrong`: "WRONG\r\n"
  - `msg_lockout`: "LOCKOUT 30s\r\n"
  - `msg_saved`: "SAVED\r\n"

---

If you want, I can also generate an **annotated version of the assembly file** with inline comments on every instruction.