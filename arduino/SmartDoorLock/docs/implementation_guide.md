# Smart Door Lock — Circuit Implementation & Ordered Steps

This guide consolidates the hardware wiring and the exact bring‑up sequence for the Arduino Uno + MFRC522 build.

## 1) What this project does (quick map)
- Reads RFID UID over SPI (MFRC522).
- Compares UID to a single authorized UID.
- Toggles lock state (unlock/lock).
- Tracks wrong attempts and enforces a lockout.
- Saves state to EEPROM on power‑fail event.

Key files:
- Main logic: [arduino/SmartDoorLock/SmartDoorLock.ino](../SmartDoorLock.ino)
- Pin mapping and build flags: [arduino/SmartDoorLock/src/config.h](../src/config.h)
- Hardware notes: [arduino/SmartDoorLock/docs/hardware_bringup.md](hardware_bringup.md)
- Wiring draft: [arduino/SmartDoorLock/docs/wiring.md](wiring.md)
- Pinout draft: [arduino/SmartDoorLock/hardware/pinout.md](../hardware/pinout.md)

## 2) Bill of materials (minimum)
- Arduino Uno (or Nano with ATmega328P)
- MFRC522 RFID reader + RFID card/tag
- Active buzzer (5V) or piezo buzzer
- LED + 330Ω resistor (optional indicator for lock output)
- Level shifter (recommended) or resistor dividers for 5V→3.3V SPI lines
- If using a real lock: NPN transistor (2N2222), base resistor (1k), flyback diode (1N4007), external 12V supply for the lock/solenoid
- Optional: voltage supervisor IC + hold‑up capacitor for power‑fail detect

## 3) Circuit wiring (hardware)

### 3.1 MFRC522 (SPI, 3.3V only)
Wire exactly like this:
- VCC → 3.3V
- GND → GND
- SDA/SS → D10
- SCK → D13
- MOSI → D11
- MISO → D12
- RST → D9
- IRQ → NC (leave unconnected)

**Level shifting (recommended):**
- Use a level shifter (or resistor divider) on **SCK, MOSI, SS, RST**.
- MFRC522 MISO (3.3V output) is usually read as HIGH by the Uno.

### 3.2 Buzzer and indicators
- Buzzer + → D8, Buzzer – → GND
- Lock output indicator LED (optional): D7 → 330Ω → LED anode, LED cathode → GND
- Status LED: D13 (built‑in LED via `LED_BUILTIN`)

### 3.3 Lock actuator (real hardware)
**Do NOT connect a solenoid/strike directly to D7.**
Use a low‑side transistor driver:
- D7 → 1k resistor → base of 2N2222
- emitter → GND
- collector → one side of solenoid/relay coil
- other side of coil → +12V (or coil supply)
- flyback diode across coil (1N4007): diode cathode to +12V, anode to collector
- **common GND** between Arduino and coil supply

### 3.4 Power‑fail detect (optional but supported)
The firmware monitors **D2** (`PIN_PWR_FAIL`) for a LOW power‑fail event.

**Option A (recommended):** voltage supervisor IC (MCP100/MCP101/TLV803). Output → D2.
Add a hold‑up capacitor so the MCU can finish EEPROM save.

**Option B (simpler):** divider to an ADC + polling (not implemented by default).

Rule of thumb for hold‑up capacitor:
$$ t = \frac{C \cdot \Delta V}{I} $$
Example: $C=4700\,\mu F$, $\Delta V=1\,V$, $I=50\,mA$ → $t\approx0.094\,s$.

## 4) Firmware configuration (before upload)

### 4.1 Select hardware vs simulation
In [arduino/SmartDoorLock/src/config.h](../src/config.h):
- **Hardware:** comment out `#define RFID_SIM_SERIAL 1`
- **Simulation:** keep it defined

### 4.2 Set your authorized UID
In [arduino/SmartDoorLock/SmartDoorLock.ino](../SmartDoorLock.ino):
- Replace `AUTH_UID` with your card UID (4 bytes)

Example:
- Printed UID: `04:AB:10:9F`
- `AUTH_UID` → `{0x04, 0xAB, 0x10, 0x9F}`

### 4.3 Pin mapping (if you changed wiring)
Edit [arduino/SmartDoorLock/src/config.h](../src/config.h):
- `PIN_BUZZER`
- `PIN_LOCK_ACTUATOR`
- `PIN_STATUS_LED`
- `PIN_RFID_SS`
- `PIN_RFID_RST`
- `PIN_PWR_FAIL`

## 5) Ordered bring‑up steps
Follow these steps in order. Do not skip ahead.

### Step 1 — Build in simulation mode (optional, but recommended)
1. Keep `RFID_SIM_SERIAL` enabled in [arduino/SmartDoorLock/src/config.h](../src/config.h).
2. Upload to Arduino.
3. Open Serial Monitor at **115200**.
4. Type a UID (e.g., `04:AB:10:9F`) and press Enter.
5. Confirm the UID prints and lock toggles on matching `AUTH_UID`.

### Step 2 — Switch to real MFRC522 hardware
1. Wire the MFRC522 (Section 3.1).
2. Comment out `#define RFID_SIM_SERIAL 1` in [arduino/SmartDoorLock/src/config.h](../src/config.h).
3. Upload to Arduino.
4. Open Serial Monitor at **115200**.
5. Confirm the boot message shows `MFRC522 VersionReg=0x91` or `0x92`.

If you see `0xFF`, check:
- VCC is **3.3V**
- Common GND
- SPI wiring (D11/D12/D13)
- SS on D10, RST on D9
- Level shifting on SCK/MOSI/SS/RST

### Step 3 — Read a tag UID
1. Tap a tag on the reader.
2. Confirm the UID prints in Serial Monitor.
3. Update `AUTH_UID` in [arduino/SmartDoorLock/SmartDoorLock.ino](../SmartDoorLock.ino).
4. Re‑upload.

### Step 4 — Validate lock logic and lockout
1. Present the authorized tag → lock toggles (buzzer short beep).
2. Present a wrong tag 3 times → 30‑second lockout.
3. Observe short beep every second during lockout.

### Step 5 — Add actuator driver
1. Build the transistor driver (Section 3.3).
2. Test with LED first, then with the real coil.
3. Confirm lock toggles only on authorized tag.

### Step 6 — Add power‑fail handling
1. Connect supervisor output to D2.
2. Add hold‑up capacitor.
3. Power cycle and confirm EEPROM restores lock state.

## 6) Quick troubleshooting checklist
- **No RFID response**: check 3.3V, SS/RST pins, SPI lines, level shifting.
- **Random resets**: add decoupling, shorten wires, separate coil supply.
- **Lock toggles incorrectly**: verify `AUTH_UID` value and byte order.
- **No lockout**: verify `MAX_WRONG_ATTEMPTS` and `LOCKOUT_SECONDS` in [arduino/SmartDoorLock/src/config.h](../src/config.h).

## 7) Next enhancements (optional)
- Add multi‑card EEPROM whitelist
- Add keypad for 2‑factor
- Add RTC timestamp for access logs

---
If you want this tailored to your exact hardware (specific lock model, power supply, level shifter part number), tell me the parts and I’ll refine the wiring and steps.