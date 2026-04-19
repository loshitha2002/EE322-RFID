# TwoFactorLock — Final PCB Wiring (12V Adapter + 12V Solenoid Lock)

This document is a **schematic-level wiring reference** for building the final PCB version of the TwoFactorLock project using:
- **ATmega328P-PU (DIP-28)** running your AVR assembly state machine
- **12V DC adapter** as the main supply
- **12V solenoid / electric strike** as the lock actuator
- **MFRC522 RFID** (3.3V, SPI)
- **16x2 I2C LCD** (typically PCF8574 backpack @ `0x27`)
- **4x4 matrix keypad**
- **Active buzzer**
- **Status LED**

> Important: a solenoid lock must be driven through a **power driver stage** (MOSFET/relay) and powered from the **12V rail**, not from the MCU.

---

## 0) Project Pin Mapping (matches your assembly)

ATmega328P DIP-28 signals used by the code:

- **Keypad Rows**: PD2, PD3, PD4, PD5
- **Keypad Cols**: PD6, PC0, PC1, PC2
- **LCD I2C**: PC4 (SDA), PC5 (SCL)
- **RFID (MFRC522) SPI**:
  - PB2 = SS (RC522 SDA/SS)
  - PB5 = SCK
  - PB3 = MOSI
  - PB4 = MISO
  - PB1 = RST
- **Buzzer**: PB0
- **Lock Output**: PD7
- **LED**: PC3

---

## 1) Power tree (12V adapter → 5V → 3.3V)

### Recommended rails
- **+12V_IN**: adapter input (lock coil power and input to buck)
- **+5V**: MCU + keypad + LCD + buzzer logic rail
- **+3V3**: MFRC522 VCC

### Components (power)
- **Adapter requirement**: regulated **12V DC**, **≥2A** recommended

- **J1 (12V IN)**: input connector (pick ONE)
  - Option A: **2-pin screw terminal**
    - Pin 1: `+12V_IN`
    - Pin 2: `GND`
  - Option B: **DC barrel jack (5.5mm/2.1mm, center-positive)**
    - Tip/center: `+12V_IN`
    - Sleeve: `GND`
- **F1 (input fuse)**: **2A slow-blow** (for 0.6A lock + startup/inrush margin)
- **D1 (reverse polarity protection)**: **SS54 Schottky diode (5A)** in series with `+12V_IN`
- **C1 (input bulk)**: 470µF / 25V electrolytic between `+12V_IN` and `GND` near J1
- **C2 (input ceramic)**: 0.1µF (100nF) between `+12V_IN` and `GND` near the buck input

#### 12V → 5V regulator (buck)
- **U1**: **LM2596 buck module** set to **5.00V** (pins: IN+, IN−, OUT+, OUT−)
- **C3 (buck output bulk)**: 470µF / 10V electrolytic on `+5V`
- **C4 (buck output ceramic)**: 0.1µF (100nF) on `+5V`

#### 5V → 3.3V regulator (LDO)
- **U2**: **AMS1117-3.3** (3.3V LDO)
- **C5 (LDO IN)**: 10µF on `+5V` close to U2 IN
- **C6 (LDO OUT)**: 10µF on `+3V3` close to U2 OUT
- Also place **100nF** at U2 IN and OUT if you can.

### Ground rule
All grounds must join into **one common ground**:
- Adapter/input ground
- Solenoid driver ground
- MCU ground
- RFID/LCD ground

---

## 2) ATmega328P core schematic (required for standalone PCB)

### MCU power pins
- Pin 7 (VCC) → `+5V`
- Pin 8 (GND) → `GND`
- Pin 20 (AVCC) → `+5V` (through optional filter below)
- Pin 22 (GND) → `GND`
- Pin 21 (AREF) → 100nF to `GND` (do not tie AREF directly to 5V unless you know why)

### Decoupling (do not skip)
Place these **as close to the ATmega pins as possible**:
- **C7**: 100nF from VCC (Pin 7) to GND
- **C8**: 100nF from AVCC (Pin 20) to GND
- **C9**: 10µF from `+5V` to `GND` near the MCU (bulk for local stability)

### Optional AVCC filter (recommended)
- `+5V` → **L1 10µH** → AVCC (Pin 20)
- AVCC → **C8 100nF** → GND

### Clock
- **Y1**: 16MHz crystal between Pin 9 (XTAL1) and Pin 10 (XTAL2)
- **C10**: 22pF from XTAL1 to GND
- **C11**: 22pF from XTAL2 to GND

### Reset
- Pin 1 (RESET / PC6) → **R1 10kΩ** to `+5V`
- Optional reset button: RESET → momentary switch → GND
- Optional noise filter: **C12 100nF** from RESET to GND (only if your programmer/reset behavior is stable)

### ISP programming header (2x3)
Add a standard AVR ISP header for flashing:
- MISO → PB4 (Pin 18)
- MOSI → PB3 (Pin 17)
- SCK  → PB5 (Pin 19)
- RESET → Pin 1
- VCC → `+5V`
- GND → `GND`

---

## 3) Peripherals wiring

## 3.1) Keypad 4x4 (8-wire)

Keypad pins (left-to-right on most membrane keypads) connect as:

- Row1 → PD2 (Pin 4)
- Row2 → PD3 (Pin 5)
- Row3 → PD4 (Pin 6)
- Row4 → PD5 (Pin 11)
- Col1 → PD6 (Pin 12)
- Col2 → PC0/A0 (Pin 23)
- Col3 → PC1/A1 (Pin 24)
- Col4 → PC2/A2 (Pin 25)

Notes:
- No external resistors required if your firmware enables pull-ups as intended.
- If your keypad is “rotated” (rows/cols swapped), swap the 4 row wires with 4 col wires.

## 3.2) I2C LCD 16x2 (PCF8574 backpack)

LCD backpack pins:
- VCC → `+5V`
- GND → `GND`
- SDA → PC4/A4 (Pin 27)
- SCL → PC5/A5 (Pin 28)

I2C pull-ups:
- Many I2C LCD backpacks already include pull-ups.
- If yours does not, add:
  - **R2 4.7kΩ** from SDA to `+5V`
  - **R3 4.7kΩ** from SCL to `+5V`

## 3.3) RFID MFRC522 (SPI, 3.3V) + level shifting

MFRC522 must be powered from **3.3V**:
- RC522 VCC → `+3V3`
- RC522 GND → `GND`

Signal connections (ATmega328P is 5V, RC522 is 3.3V):

- RC522 SDA/SS  ← PB2 (Pin 16) **through level shifting**
- RC522 SCK     ← PB5 (Pin 19) **through level shifting**
- RC522 MOSI    ← PB3 (Pin 17) **through level shifting**
- RC522 RST     ← PB1 (Pin 15) **through level shifting**
- RC522 MISO    → PB4 (Pin 18) (usually OK direct; it is 3.3V output)
- RC522 IRQ: leave unconnected

### Level shifting options (choose one)

**Option A (recommended): 4-channel MOSFET level shifter module**
- Use a BSS138-based bidirectional level shifter board.
- HV side = `+5V` (ATmega side)
- LV side = `+3V3` (RC522 side)
- Shift these lines: SS, SCK, MOSI, RST

**Option B (simple): resistor dividers (unidirectional down-shift)**
For each ATmega → RC522 line (SS, SCK, MOSI, RST):
- R_top = 2.0kΩ from ATmega pin to RC522 pin
- R_bottom = 3.3kΩ from RC522 pin to GND
This gives about 3.3V when driven HIGH from 5V.

---

## 4) Lock driver (12V solenoid) — exact schematic wiring

### Goal
Use PD7 (ATmega output) to switch the **low side** of the solenoid with an N-channel MOSFET.

### Parts (lock driver)
- **Q1**: **AO3400A** logic-level N-MOSFET (SOT-23), low-side switch for **0.6A** coil
- **R4 (gate series resistor)**: 100Ω
- **R5 (gate pulldown)**: 100kΩ (gate to GND)
- **D2 (flyback diode)**: **1N5408** (3A) across the solenoid coil
- **J2 (LOCK OUT)**: 2-pin screw terminal
  - Pin 1: `+12V_IN`
  - Pin 2: `LOCK_COIL_NEG` (to MOSFET drain)

### Connections (netlist style)

- Solenoid coil:
  - Coil+ → `+12V_IN`
  - Coil− → `LOCK_COIL_NEG`

- MOSFET Q1 (low-side switch):
  - Q1 **Source** → `GND`
  - Q1 **Drain** → `LOCK_COIL_NEG`
  - Q1 **Gate** → `LOCK_GATE` (from PD7 through R4)

- Gate drive:
  - PD7 (Pin 13) → R4 (100Ω) → `LOCK_GATE` → Q1 Gate
  - R5 (100kΩ) from `LOCK_GATE` to `GND`

- Flyback diode D2 (across the solenoid coil):
  - D2 **Cathode** → `+12V_IN` (coil+)
  - D2 **Anode** → `LOCK_COIL_NEG` (coil− / MOSFET drain)

### Notes (important)
- If the lock does the opposite of what you expect (fail-secure vs fail-safe), you fix it in **software logic**, not wiring.
- Keep the high-current solenoid loop (adapter → coil → MOSFET → ground) physically short and with thick traces.
- For **0.6A** coil current on 1oz copper, use at least **1.0mm trace width** for the coil path (wider is better).

---

## 5) Buzzer + LED

### Buzzer (active buzzer)
- PB0 (Pin 14) → Buzzer `+`
- Buzzer `−` → `GND`

If your buzzer draws more than ~20mA, add an NPN driver:
- PB0 → 1kΩ → base of 2N2222
- emitter → GND
- collector → buzzer −
- buzzer + → +5V

### LED indicator
- PC3 (Pin 26) → **R6 330Ω** → LED anode (+)
- LED cathode (−) → `GND`

---

## 6) Connector checklist (recommended)

- J1: 12V adapter input (screw terminal OR barrel jack)
- J2: Solenoid lock output (2-pin)
- J3: Keypad (8-pin)
- J4: LCD I2C (4-pin)
- J5: MFRC522 header (7-pin: 3V3, GND, SS, SCK, MOSI, MISO, RST)
- J6: ISP (2x3)

---

## 7) Quick bring-up order (hardware debug)

1) Power only: confirm `+5V` and `+3V3` are correct.
2) MCU only: confirm reset + crystal (program over ISP).
3) LCD: confirm it shows text.
4) Keypad: confirm keys register.
5) MFRC522: confirm it reads UID reliably.
6) Solenoid driver: test with a dummy load first (12V lamp), then solenoid.

---

## 8) Schematic mini-diagram (lock driver)

```
      +12V_IN
         |
         |      D2 (flyback)
         +----->|-----+
         |            |
      [ SOLENOID ]    |
         |            |
         +------------+---- LOCK_COIL_NEG ---- Drain (Q1) MOSFET
                                      Source (Q1) ---- GND

PD7 --- R4 100Ω --- Gate (Q1)
                 |
                 R5 100k
                 |
                GND
```
