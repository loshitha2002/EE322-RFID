# TwoFactorLock — Dot/Perf Board Build Guide (12V Adapter + Buck Converters + Level Shifting)

This guide is for rebuilding your working TwoFactorLock circuit on a **dot board / perf board** (soldered), since the PCB is not working.

Design goals:
- Use a **12V DC adapter** (no battery)
- Make stable rails using **buck converters**
- Protect the **MFRC522 (3.3V)** inputs using **level shifting**
- Build in a way that is easy to debug and rework

> Recommended approach: build and test in stages (power → MCU → LCD → keypad → RFID → lock driver). Do not solder everything first.

---

## 1) “Must-have” component list (BOM)

### 1.1 Core controller (ATmega328P standalone)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | U1 | ATmega328P-PU (DIP-28) | Main MCU |
| 1 | Socket | DIP-28 socket | Strongly recommended (protects MCU from heat) |
| 1 | Y1 | 16 MHz crystal | HC49S or small SMD-on-adapter is OK |
| 2 | C1, C2 | 22 pF ceramic | Crystal caps |
| 1 | R1 | 10 kΩ | RESET pull-up |
| 2 | C3, C4 | 100 nF ceramic | Decoupling: VCC–GND and AVCC–GND (place closest to MCU pins) |
| 1 | C5 | 10 µF electrolytic/tantalum | Bulk near MCU (5V to GND) |
| 1 | C6 | 100 nF ceramic | AREF to GND (recommended) |

**ATmega328P power pins (DIP-28):**
- VCC = pin 7, GND = pin 8
- AVCC = pin 20, GND = pin 22
- AREF = pin 21

### 1.2 Power (12V → 5V → 3.3V)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | PSU | 12V DC adapter | ≥2A recommended (lock inrush + margin) |
| 1 | J1 | 2-pin screw terminal OR DC barrel jack | 12V input |
| 1 | F1 | Fuse (optional) | 2A slow-blow recommended |
| 1 | D1 | Schottky diode (optional) | SS54 (reverse polarity protection) |
| 1 | C7 | Electrolytic | 470 µF / 25V on 12V input (near input connector) |
| 1 | C8 | Ceramic | 100 nF on 12V input (near input connector) |
| 1 | U2 | Buck converter module | **12V → 5V** (e.g., LM2596 module) |
| 1 | C9 | Electrolytic | 220–470 µF / 10V on 5V rail near buck output |
| 1 | C10 | Ceramic | 100 nF on 5V rail near buck output |
| 1 | U3 | Buck converter module | **5V → 3.3V** (recommended) OR 12V→3.3V buck |
| 1 | C11 | Electrolytic | 47–220 µF on 3.3V rail near U3 output |
| 1 | C12 | Ceramic | 100 nF on 3.3V rail near U3 output |

**Important:** If you use an **AMS1117-3.3** LDO instead of a 3.3V buck, it needs proper caps close to it (commonly 10µF in/out). A 3.3V buck is usually more forgiving and cooler.

### 1.3 LCD (I2C 16x2 with PCF8574 backpack)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | LCD1 | 16x2 LCD with I2C backpack | Usually address 0x27 or 0x3F |
| 1 | J2 | 4-pin header | VCC, GND, SDA, SCL |
| 0–2 | R2, R3 | 4.7 kΩ | I2C pull-ups to 5V (only if your backpack does not have pull-ups) |

### 1.4 Keypad (4x4 matrix)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | KP1 | 4x4 matrix keypad | 8-wire |
| 1 | J3 | 8-pin header | Keypad connector |

### 1.5 RFID (MFRC522 / RC522)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | RFID1 | MFRC522 / RC522 module | Must be powered from 3.3V |
| 1 | J4 | 7–8 pin header | 3V3, GND, SS, SCK, MOSI, MISO, RST (IRQ optional) |
| 1 | LS1 | Level shifter module | **BSS138 4-channel** level shifter recommended |

**Level shifting lines (ATmega 5V → RC522 3.3V):**
- SS, SCK, MOSI, RST should be level shifted
- MISO (3.3V output) usually works directly into ATmega

### 1.6 Lock driver (12V solenoid)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | Lock | 12V solenoid / strike | ~0.6A typical (your value may differ) |
| 1 | J5 | 2-pin screw terminal | Lock output |
| 1 | Q1 | Logic-level N-MOSFET | AO3400A / IRLZ44N / IRLZ34N etc. (choose one you have) |
| 1 | R4 | 100–220 Ω | Gate series resistor |
| 1 | R5 | 100 kΩ | Gate pulldown to GND |
| 1 | D2 | Flyback diode | 1N5408 or SS54/SS34 (must handle coil current) |

### 1.7 LED + buzzer

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | LED1 | LED | Any color |
| 1 | R6 | 330 Ω | LED resistor |
| 1 | BZ1 | Active buzzer | If it draws >20mA, use a transistor driver |
| 0–1 | Q2 | NPN transistor (optional) | 2N2222 + 1k base resistor if needed |
| 0–1 | R7 | 1 kΩ (optional) | Buzzer transistor base resistor |

### 1.8 Programming / debug connectors (highly recommended)

| Qty | Part | Value / Type | Notes |
|---:|------|--------------|------|
| 1 | J6 | 2x3 AVR ISP header | MISO/MOSI/SCK/RESET/VCC/GND |
| 1 | J7 | 3-pin UART header (optional) | TX, RX, GND for debugging if you have it |

### 1.9 Build materials

| Qty | Part | Notes |
|---:|------|------|
| 1 | Perf board | Dot board / stripboard / perf board |
| 1 | Solid core wire | 22–24 AWG for jumpers |
| 1 | Thicker wire | 18–20 AWG for lock current path |
| 1 | Heatshrink | For exposed joints |
| — | Male headers / dupont | For module connections |

---

## 2) Suggested wiring map (matches your assembly code)

This matches the existing project docs and firmware variants.

- Keypad Rows: PD2, PD3, PD4, PD5
- Keypad Cols: PD6, PC0, PC1, PC2
- LCD I2C: PC4 (SDA), PC5 (SCL)
- RFID SPI:
  - PB2 = SS
  - PB5 = SCK
  - PB3 = MOSI
  - PB4 = MISO
  - PB1 = RST
- Buzzer: PB0

**Lock + LED pins depend on firmware variant:**
- Default/breadboard: Lock = PD7, LED = PC3
- PCB-variant file: Lock = PC3, LED = PD7

> Choose ONE wiring and flash the matching firmware.

---

## 3) Physical build rules (this prevents 80% of failures)

- Make 3 “rails” on the perfboard: **GND**, **+5V**, **+3V3**.
- Keep the **lock current loop** physically separated from MCU signals:
  - 12V → lock → MOSFET → GND return should use **thick wire** and short path.
- Put the **100nF decoupling caps** directly at the MCU pins:
  - C3: pin 7 to pin 8
  - C4: pin 20 to pin 22
- Run **one common ground** (star-ish): buck grounds, MCU ground, RFID ground, LCD ground, MOSFET source ground must be common.

---

## 4) Soldering process (step-by-step)

### Step 0 — Tools checklist
- Multimeter
- Soldering iron + solder + flux
- Side cutters

### Step 1 — Mount power input + buck converters
1) Solder J1 (12V input connector).
2) Solder C7 (470µF) and C8 (100nF) across 12V and GND near J1.
3) Mount U2 (12→5 buck). Set it to **5.00V** before connecting MCU.
4) Add C9 (220–470µF) + C10 (100nF) on the **5V output**.
5) Mount U3 (5→3.3 buck). Set it to **3.30V**.
6) Add C11 (47–220µF) + C12 (100nF) on the **3.3V output**.

**Test now:**
- Power from 12V adapter.
- Measure: 12V, 5V, 3.3V.

### Step 2 — Mount MCU socket + minimum “it must boot” parts
1) Solder the DIP-28 socket.
2) Wire +5V and GND to MCU pins:
   - +5V → pin 7 and pin 20
   - GND → pin 8 and pin 22
3) Solder C3 (100nF) at pins 7–8 and C4 (100nF) at pins 20–22.
4) Solder C5 (10µF) across +5V and GND near the socket.
5) Solder reset pull-up: R1 10k from RESET pin 1 to +5V.
6) Solder crystal Y1 between pins 9 and 10, with C1/C2 (22pF) from each pin to GND.
7) Solder C6 100nF from AREF (pin 21) to GND.

**Test now (recommended):**
- Flash firmware using AVR ISP header (Step 3).

### Step 3 — Add ISP header (so you can program anytime)
1) Solder J6 2x3 header.
2) Wire:
   - MOSI → PB3 (pin 17)
   - MISO → PB4 (pin 18)
   - SCK → PB5 (pin 19)
   - RESET → pin 1
   - VCC → +5V
   - GND → GND

### Step 4 — Add LCD (I2C) next
1) Solder J2 (LCD header).
2) Wire LCD:
   - SDA → PC4 (pin 27)
   - SCL → PC5 (pin 28)
   - VCC → +5V, GND → GND
3) If your LCD backpack has no pullups, add R2/R3 (4.7k) from SDA/SCL to +5V.

**Test now:** LCD should show text (or at least not hang the program).

### Step 5 — Add keypad
1) Solder J3 (8-pin header).
2) Wire rows/cols per your mapping.

**Test now:** keys should register.

### Step 6 — Add RFID (RC522) with level shifter
1) Solder J4 (RC522 header).
2) Power RC522 only from **3.3V**.
3) Insert LS1 (level shifter module):
   - HV = +5V, LV = +3.3V, grounds common
   - Shift SS, SCK, MOSI, RST
   - MISO direct to PB4

**Test now:** tap card; UID should be read reliably.

### Step 7 — Add lock MOSFET driver last
1) Solder J5 (lock screw terminal).
2) Build MOSFET stage:
   - MOSFET source → GND
   - MOSFET drain → lock negative
   - lock positive → +12V
   - diode across lock coil: cathode to +12V, anode to drain/lock-
   - gate series resistor 100–220Ω
   - gate pulldown 100k to GND

**Test now:** unlock should energize lock (be careful: solenoid can get hot).

---

## 5) Very common perfboard mistakes (quick checks)

- **AVCC not connected**: MCU runs weird and I2C on PC4/PC5 fails.
- **No 100nF near MCU**: random resets, LCD stuck blue, RFID unstable.
- **RC522 powered from 5V**: can permanently damage the module.
- **No level shifting**: RC522 works “sometimes” then fails.
- **No common ground** between 12V/5V/3.3V: nothing works correctly.

---

## 6) If you want, I can tailor this to your exact firmware file

Tell me which one you will flash:
- default mapping (Lock=PD7, LED=PC3)
- PC3-lock variant (Lock=PC3, LED=PD7)

Then I’ll update the lock/LED section so it matches exactly and there is no confusion.
