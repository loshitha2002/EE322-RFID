# Two-Factor (PIN + RFID) Lock System

This folder contains the **Hardware Prototype** code for the Mid-Evaluation.

## Logic Overview
The system uses a **Hybrid Architecture**:
1.  **C++ (Arduino):** Handles the complex hardware drivers (LCD I2C, Keypad Matrix, SPI RFID).
2.  **Assembly (AVR):** Handles the core security verification logic (checking if the PIN matches, checking if the UID matches).

## Pinout (ATmega328P / Arduino Uno)
| Component | Pin | Note |
|---|---|---|
| **Keypad R1** | D2 | |
| **Keypad R2** | D3 | |
| **Keypad R3** | D4 | |
| **Keypad R4** | D5 | |
| **Keypad C1** | D6 | |
| **Keypad C2** | A0 | Configured as Digital |
| **Keypad C3** | A1 | Configured as Digital |
| **Keypad C4** | A2 | Configured as Digital |
| **Buzzer** | D8 | |
| **Lock/Relay** | D7 | |
| **LED** | A3 | Configured as Digital |
| **RFID SDA** | D10 | |
| **RFID SCK** | D13 | |
| **RFID MOSI** | D11 | |
| **RFID MISO** | D12 | |
| **RFID RST** | D9 | |
| **LCD SDA** | A4 | I2C Data |
| **LCD SCL** | A5 | I2C Clock |

## Setup Instructions
1. Open this folder in VS Code.
2. Ensure you have the required Arduino Libraries installed via Library Manager:
   - `Keypad` by Mark Stanley
   - `MFRC522` by GithubCommunity
   - `LiquidCrystal_I2C` by Frank de Brabander
3. Compiling:
   - The file `src/logic.S` helps implement the secret checks.
   - Arduino IDE handles the linking of `.S` files automatically if they are in the `src` subfolder (or sometimes root, depending on IDE version).
   - If using Arduino IDE 1.8.x, you might need to move `src/logic.S` to the same folder as the `.ino` file.

## How to Test
1. Power on. LCD says "READY".
2. Press any key. LCD says "Enter PIN".
3. Type `1-2-3-4` then `#`.
4. If correct, LCD says "Scan Card".
5. Touch RFID card.
6. If correct, Door Unlocks.
