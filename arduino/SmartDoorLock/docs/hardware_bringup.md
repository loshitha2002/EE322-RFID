# Hardware bring-up (Arduino Uno + MFRC522)

This guide assumes your **simulation works** and you are now moving to **real hardware**.

## 1) Switch build from simulation → hardware

Your code already supports both modes.

- **Simulation (Proteus):** `RFID_SIM_SERIAL` defined
- **Real MFRC522 hardware:** `RFID_SIM_SERIAL` NOT defined

So for real hardware, in `src/config.h`:
- Comment out the line `#define RFID_SIM_SERIAL 1`

Nothing else needs to change to keep simulation working later.

## 2) MFRC522 wiring (SPI)

MFRC522 is a 3.3V device.

**MFRC522 → Arduino Uno**
- VCC → **3.3V** (do not use 5V)
- GND → GND
- SDA / SS → D10
- SCK → D13
- MOSI → D11
- MISO → D12
- RST → D9
- IRQ → (leave unconnected)

### Important: 5V to 3.3V level shifting

Arduino Uno outputs are 5V. For reliability and to protect the MFRC522:
- Use a **level shifter** (or a resistor divider) on **SCK, MOSI, SS, RST**.
- MFRC522 **MISO (3.3V output)** is usually read OK by the Uno as HIGH.

If you don’t have a level shifter, it may still work short-term, but it’s not recommended.

## 3) Upload + verify MFRC522 communication

1. Upload the sketch to the Uno.
2. Open Serial Monitor at **115200**.
3. On boot you should see something like:
   - `MFRC522 VersionReg=0x91` or `0x92` (varies)

If you see `0xFF`, SPI isn’t talking to the reader.

### If VersionReg is 0xFF (quick checks)

- VCC is **3.3V**, not 5V
- Common GND connected
- D10 is wired to **SDA/SS**
- SPI pins are correct (Uno: D11 MOSI, D12 MISO, D13 SCK)
- RST wired to D9
- Try shorter wires
- Add level shifting on SCK/MOSI/SS/RST

## 4) Read a card UID and set your authorized UID

When you tap a card/tag, the sketch prints:
- `UID (4 bytes): xx:xx:xx:xx`

Copy that 4-byte UID into the sketch constant:
- `AUTH_UID[4]` in `SmartDoorLock.ino`

Then re-upload.

## 5) LED + buzzer wiring (quick prototype)

### LED (status)
- D13 (built-in LED) already exists on Uno (your code uses `LED_BUILTIN`)

### Lock actuator output indicator (D7)
If you want a separate LED showing the lock output:
- D7 → 330Ω resistor → LED anode (+)
- LED cathode (–) → GND

### Buzzer (D8)
For an **active buzzer**:
- D8 → buzzer (+)
- GND → buzzer (–)

## 6) Real lock actuator (DO NOT connect directly)

If you use a solenoid / strike / relay, do not connect it to D7 directly.

Recommended driver (low-side NPN):
- D7 → 1k resistor → base of 2N2222
- emitter → GND
- collector → one side of solenoid/relay coil
- other side of coil → +12V (or your coil supply)
- flyback diode across the coil (1N4007): diode cathode to +12V, anode to collector
- common GND between Uno and coil supply

## 7) Power-failure handling (real hardware options)

Your current firmware saves state when a **digital power-fail input** goes LOW (D2).

### Option A (recommended): Voltage supervisor IC
Use a supervisor/reset IC that asserts LOW when VCC drops below a threshold.
- Example families: MCP100/MCP101, TLV803, etc.
- Connect supervisor output to **D2**.
- Add a hold-up capacitor so the MCU has time to write EEPROM.

### Option B: Divider to an ADC + polling (software detect)
Use a resistor divider from VCC to an analog pin (e.g., A0), then poll and save when it drops.
This is easier to prototype but is less “instant” than an interrupt.

### Hold-up capacitor sizing (rule of thumb)
You need enough time to save a few bytes to EEPROM.
A rough estimate:

- Discharge time:  t = C * ΔV / I

Example:
- Load current I = 50 mA
- Allowable voltage drop ΔV = 1 V
- Capacitor C = 4700 µF

t ≈ 4700e-6 * 1 / 0.05 ≈ 0.094 s (94 ms)

That’s typically enough for a small EEPROM save if you keep it short.

## 8) Practical bring-up order

1. Confirm `VersionReg` is not 0xFF.
2. Confirm UID prints repeatedly.
3. Set `AUTH_UID` and confirm lock toggles.
4. Confirm 3 wrong attempts triggers 30s lockout.
5. Add the actuator driver (transistor + diode) and test.
6. Implement power-fail hardware and test saving/restoring.
