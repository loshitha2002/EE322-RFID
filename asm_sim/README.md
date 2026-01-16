# AVR Assembly Simulation (Proteus) — Smart Door Lock Logic

This folder simulates the **logic** of your smart door lock in **ATmega328P assembly** without RFID hardware.

What you can validate here:
- Wrong attempt counter (3)
- 30 second lockout timer
- Buzzer activity during lockout
- Power-fail save to EEPROM + restore after reset

## 1) Install build tools (Windows)

VS Code is the editor; you still need an AVR toolchain.

### Option A (recommended): MSYS2 (UCRT64)
1. Install MSYS2: https://www.msys2.org
2. IMPORTANT: open **MSYS2 UCRT64** (or **MSYS2 MINGW64**) from the Start Menu.
   - Do **not** use the plain **MSYS** shell for AVR packages.

3. In **MSYS2 UCRT64**, run:

```bash
pacman -Syu
pacman -S --needed \
  mingw-w64-ucrt-x86_64-make \
  mingw-w64-ucrt-x86_64-avr-gcc \
  mingw-w64-ucrt-x86_64-avr-binutils \
  mingw-w64-ucrt-x86_64-avr-libc \
  mingw-w64-ucrt-x86_64-avrdude
```

4. Add to Windows PATH:
- `C:\msys64\ucrt64\bin`

Note: the PATH line above is a **Windows Environment Variable setting**, not a command to run inside MSYS2.

Quick workaround (PowerShell, current terminal only):

```powershell
$env:Path += ";C:\\msys64\\ucrt64\\bin"
```

On some MSYS2 installs, the executable name is `mingw32-make.exe` (not `make.exe`) in `C:\msys64\ucrt64\bin`.

Use either of these options:
- Run `mingw32-make` instead of `make`
- Or create a PowerShell alias (current terminal only):

```powershell
Set-Alias make mingw32-make
```

Verify in VS Code terminal:

```powershell
avr-gcc --version
avr-objcopy --version
make --version
```

If those commands are still not found:
- Close and re-open VS Code (it needs to reload PATH)
- Confirm `C:\msys64\ucrt64\bin` is in your PATH

### Option B (fallback): Arduino IDE toolchain
If you already have Arduino IDE installed, you can compile/upload Arduino sketches without MSYS2.
For pure AVR assembly builds, MSYS2 is still the cleanest, but Arduino IDE can be used as a fallback toolchain if your course allows it.

## 2) Build the HEX in VS Code

Important: the firmware’s UART timing depends on `F_CPU` in `asm_sim/Makefile`.
Set Proteus MCU clock to match, or change `F_CPU` in the Makefile and rebuild.
Supported values: `1000000`, `8000000`, `16000000`.

From VS Code terminal:

```powershell
cd "e:\Pera bots\EE322-RFID\asm_sim"
mingw32-make
```

Output:
- `main.hex`

Or use VS Code task:
- `Terminal -> Run Task -> Build AVR ASM sim (make)`

## 3) Proteus schematic wiring (ATMEGA328P)

Use the **ATMEGA328P** part (standalone MCU). This matches your embedded systems module.

### Power + clock
- VCC and AVCC -> +5V
- GND and AGND -> GND
- AREF -> 100nF to GND (recommended)
- Clock:
  - Either use 16 MHz crystal on XTAL1/XTAL2 (with 22pF caps),
  - Or set the Proteus MCU clock to 16 MHz if using an internal model.

### UART Virtual Terminal
- Virtual Terminal TXD -> PD0 / RXD
- Virtual Terminal RXD -> PD1 / TXD
- Virtual Terminal GND -> GND
- Baud: **9600**

Note: firmware uses UART double-speed mode (U2X) internally; keep the terminal at **9600**.

Expected output after reset:
- You should see a `.` printed about once per second (heartbeat)
- You should also see `!` and the banner text at startup

If you see garbage characters (like `€` or random symbols), your Proteus MCU clock does not match the firmware build clock.
- Check the ATmega328P **Clock Frequency** property in Proteus
- Then load the matching HEX:
  - 16 MHz: `e:\Pera bots\EE322-RFID\asm_sim\main_16.hex`
  - 12 MHz: `e:\Pera bots\EE322-RFID\asm_sim\main_12.hex`
  - 11.0592 MHz: `e:\Pera bots\EE322-RFID\asm_sim\main_11.hex`
  - 8 MHz: `e:\Pera bots\EE322-RFID\asm_sim\main_8.hex`
  - 1 MHz: `e:\Pera bots\EE322-RFID\asm_sim\main_1.hex`

If you see no text in the terminal:
- Reset the MCU and look for a startup LED blink on PD7 (3 slow blinks)
  - If LED blinks: CPU is running; fix UART wiring/baud/clock
  - If LED does not blink: check power/clock/program file

### Outputs
- PD7 -> 330Ω resistor -> LED anode (+)
- LED cathode (-) -> GND

- PB0 -> active buzzer (+)
- buzzer (-) -> GND

### Power-fail input
- PD2 / INT0 -> push button -> GND
- No external resistor needed (firmware enables internal pull-up)

## 4) Load program into Proteus

1. Double-click the ATMEGA328P component
2. Set **Program File** to this file:
   - `e:\Pera bots\EE322-RFID\asm_sim\main.hex`
3. Set clock to **16 MHz**
4. Run simulation

## 5) How to test (commands)

In the Virtual Terminal, type:
- `A` : Authorized (sets unlocked)
- `W` : Wrong attempt (increments counter)
- After 3 wrong attempts: lockout starts at 30 seconds
- `P` : Save state to EEPROM (simulated power-fail)

Expected behavior:
- `A` prints `OK (UNLOCK)` and PD7 LED turns on
- `W` prints `WRONG`
- On 3rd `W`, prints `LOCKOUT 30s` and buzzer toggles every second
- Press the PD2 button: triggers EEPROM save (the firmware prints `EEPROM SAVED` after it writes)
- Reset the MCU: state is restored from EEPROM

## 6) Next step (later)

Once this logic is stable, replace the UART-simulated RFID events with real MFRC522 SPI routines in assembly.
