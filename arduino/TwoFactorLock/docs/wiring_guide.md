# Two-Factor Lock - Complete Wiring Guide (A to Z)

## ATmega328P DIP-28 Pin Map

```
                      ┌──────────┐
         (RESET) PC6 ─┤1       28├─ PC5 (SCL/A5)  --> LCD SCL
           (RXD) PD0 ─┤2       27├─ PC4 (SDA/A4)  --> LCD SDA
           (TXD) PD1 ─┤3       26├─ PC3 (A3)      --> LED (+)
    (INT0/D2)   PD2 ─┤4       25├─ PC2 (A2)      --> Keypad Col 4
           (D3)  PD3 ─┤5       24├─ PC1 (A1)      --> Keypad Col 3
           (D4)  PD4 ─┤6       23├─ PC0 (A0)      --> Keypad Col 2
                 VCC ─┤7       22├─ GND
                 GND ─┤8       21├─ AREF
           (XTAL1)   ─┤9       20├─ AVCC
           (XTAL2)   ─┤10      19├─ PB5 (SCK/D13) --> RFID SCK
           (D5)  PD5 ─┤11      18├─ PB4 (MISO/D12)--> RFID MISO
           (D6)  PD6 ─┤12      17├─ PB3 (MOSI/D11)--> RFID MOSI
           (D7)  PD7 ─┤13      16├─ PB2 (SS/D10)  --> RFID SDA(SS)
           (D8)  PB0 ─┤14      15├─ PB1 (D9)      --> RFID RST
                      └──────────┘
```

---

## Components Required

| # | Component | Quantity | Notes |
|---|-----------|----------|-------|
| 1 | ATmega328P-PU (DIP-28) | 1 | The main microcontroller |
| 2 | 16 MHz Crystal Oscillator | 1 | For clock |
| 3 | 22pF Ceramic Capacitor | 2 | For crystal |
| 4 | 10kΩ Resistor | 1 | For reset pull-up |
| 5 | 330Ω Resistor | 1 | For LED |
| 6 | 4x4 Matrix Keypad | 1 | Membrane type |
| 7 | RC522 RFID Module | 1 | Comes with card/tag |
| 8 | I2C LCD 16x2 (with backpack) | 1 | Must have I2C module soldered |
| 9 | LED (Blue or Green) | 1 | Door lock indicator |
| 10 | Active Buzzer | 1 | Alarm/feedback |
| 11 | Breadboard | 1 | Full size recommended |
| 12 | Jumper Wires | ~30 | Male-Male and Male-Female |
| 13 | Arduino Uno | 1 | Used ONLY as programmer |
| 14 | USB-TTL Adapter (Optional) | 1 | For serial debug |
| 15 | 3.3V Source | 1 | For RFID (use Uno 3.3V pin or AMS1117) |

---

## STEP A: Place ATmega328P on Breadboard

1. Place the chip across the CENTER GROOVE of the breadboard.
2. The NOTCH/DOT faces LEFT (Pin 1 is top-left).
3. Connect the TOP rail as +5V and BOTTOM rail as GND.

---

## STEP B: Power Connections (4 wires)

| From (Chip Pin) | To | Wire Color |
|---|---|---|
| Pin 7 (VCC) | +5V Rail | Red |
| Pin 8 (GND) | GND Rail | Black |
| Pin 20 (AVCC) | +5V Rail | Red |
| Pin 22 (GND) | GND Rail | Black |

---

## STEP C: Reset Circuit (1 resistor + optional button)

| From | To | Component |
|---|---|---|
| Pin 1 (RESET) | +5V Rail | 10kΩ Resistor |
| Pin 1 (RESET) | GND Rail | Push Button (optional, for manual reset) |

---

## STEP D: Crystal Oscillator (1 crystal + 2 capacitors)

| From | To | Component |
|---|---|---|
| Pin 9 (XTAL1) | Pin 10 (XTAL2) | 16 MHz Crystal (one leg each) |
| Pin 9 | GND Rail | 22pF Capacitor |
| Pin 10 | GND Rail | 22pF Capacitor |

---

## STEP E: 4x4 Keypad (8 wires)

Code: `rowPins = {2, 3, 4, 5}`, `colPins = {6, A0, A1, A2}`

Keypad has 8 pins. Looking at the keypad face-up, pins go Left to Right.

| Keypad Pin (L to R) | Function | Arduino Pin | Chip Physical Pin |
|---|---|---|---|
| Pin 1 | Row 1 | D2 | **Pin 4** (PD2) |
| Pin 2 | Row 2 | D3 | **Pin 5** (PD3) |
| Pin 3 | Row 3 | D4 | **Pin 6** (PD4) |
| Pin 4 | Row 4 | D5 | **Pin 11** (PD5) |
| Pin 5 | Col 1 | D6 | **Pin 12** (PD6) |
| Pin 6 | Col 2 | A0 | **Pin 23** (PC0) |
| Pin 7 | Col 3 | A1 | **Pin 24** (PC1) |
| Pin 8 | Col 4 | A2 | **Pin 25** (PC2) |

**Note:** Some keypads have Rows and Cols swapped. If keys don't work, swap the Row and Col wires.

---

## STEP F: RFID Module RC522 (7 wires)

Code: `SS_PIN = 10`, `RST_PIN = 9`

**WARNING: RC522 VCC must be 3.3V. Do NOT connect to 5V!**

| RC522 Pin | Arduino Pin | Chip Physical Pin | Note |
|---|---|---|---|
| 3.3V | -- | -- | Connect to 3.3V source ONLY |
| RST | D9 | **Pin 15** (PB1) | |
| GND | -- | GND Rail | |
| IRQ | -- | -- | NOT connected (leave empty) |
| MISO | D12 | **Pin 18** (PB4) | |
| MOSI | D11 | **Pin 17** (PB3) | |
| SCK | D13 | **Pin 19** (PB5) | |
| SDA (SS) | D10 | **Pin 16** (PB2) | |

### Where to get 3.3V:
- Option 1: Use the 3.3V pin from your Arduino Uno (just for powering RC522).
- Option 2: Use an AMS1117 3.3V voltage regulator module.

---

## STEP G: I2C LCD Display 16x2 (4 wires)

The LCD must have the I2C backpack module soldered on the back.

| LCD I2C Pin | Arduino Pin | Chip Physical Pin |
|---|---|---|
| GND | -- | GND Rail |
| VCC | -- | +5V Rail |
| SDA | A4 | **Pin 27** (PC4) |
| SCL | A5 | **Pin 28** (PC5) |

**Troubleshooting:** If screen is blue but no text, turn the blue potentiometer
on the back of the I2C module with a screwdriver until text appears.

**I2C Address:** Most modules use 0x27. If LCD doesn't work, try 0x3F.

---

## STEP H: LED - Door Lock Indicator (1 LED + 1 resistor)

Code: `PIN_LED = A3`

| From | To | Component |
|---|---|---|
| Chip **Pin 26** (PC3/A3) | LED Anode (+) (long leg) | Wire |
| LED Cathode (-) (short leg) | GND Rail | 330Ω Resistor |

---

## STEP I: Buzzer (2 wires)

Code: `PIN_BUZZER = 8` (PB0)

| From | To |
|---|---|
| Chip **Pin 14** (PB0/D8) | Buzzer (+) |
| Buzzer (-) | GND Rail |

---

## STEP J: Lock Relay (OPTIONAL - Skip for Mid-Eval)

Code: `PIN_LOCK = 7` (PD7)

| From | To |
|---|---|
| Chip **Pin 13** (PD7/D7) | Relay Signal IN |
| Relay VCC | +5V Rail |
| Relay GND | GND Rail |

For Mid-Eval, the LED on A3 already shows the lock state. Skip this step.

---

## STEP K: Programming (Temporary - Remove After Flashing)

Use Arduino Uno with "ArduinoISP" sketch uploaded.

| Arduino Uno Pin | Chip Physical Pin | Function |
|---|---|---|
| D10 | **Pin 1** (Reset) | Chip Reset |
| D11 | **Pin 17** (MOSI) | Data Out |
| D12 | **Pin 18** (MISO) | Data In |
| D13 | **Pin 19** (SCK) | Clock |
| 5V | +5V Rail | Power |
| GND | GND Rail | Ground |

**After flashing, REMOVE these 6 wires!**

---

## Wire Count Summary

| Section | Wires | Components |
|---|---|---|
| Power (Step B) | 4 | -- |
| Reset (Step C) | 1 | 10kΩ Resistor |
| Crystal (Step D) | 2 | Crystal + 2x 22pF Caps |
| Keypad (Step E) | 8 | -- |
| RFID (Step F) | 7 | -- |
| LCD (Step G) | 4 | -- |
| LED (Step H) | 2 | 330Ω Resistor |
| Buzzer (Step I) | 2 | -- |
| **TOTAL** | **30 wires** | **5 small components** |

---

## How to Flash the Code

### Prepare Arduino Uno as Programmer
1. Plug Arduino Uno into PC via USB.
2. Open Arduino IDE.
3. Go to File > Examples > 11.ArduinoISP > ArduinoISP.
4. Upload this sketch to the Uno.

### Connect Programmer (Step K wires)
5. Wire the 6 connections from Step K above.

### Upload Your Code
6. Open `TwoFactorLock.ino` in Arduino IDE.
7. Select Board: "Arduino Uno".
8. Select Programmer: "Arduino as ISP".
9. Click Sketch > Upload Using Programmer.
10. Wait for "Done uploading" message.

### Disconnect Programmer
11. Remove the 6 programming wires (Step K).
12. Your chip now has the code permanently stored.

---

## Testing Procedure

1. Power on the breadboard (+5V).
2. LCD displays: "System Booting" then "READY. Press Key".
3. Press any key on keypad -> LCD says "Enter PIN:".
4. Type 1-2-3-4 on keypad (you see **** on LCD).
5. Press # to confirm.
6. LCD says "PIN OK! Scan Card".
7. Tap your RFID card/tag on the RC522 module.
8. LCD says "ACCESS GRANTED".
9. LED turns ON, Buzzer beeps.
10. After 3 seconds, LED turns OFF, system resets.

### If Wrong PIN:
- LCD says "Wrong PIN!" with long buzzer beep.

### If Wrong Card:
- LCD says "Unknown Card" with long buzzer beep.

---

## Important Notes

1. RFID module MUST be powered by 3.3V (not 5V).
2. If LCD shows nothing, adjust the blue potentiometer on the back.
3. If keypad keys are jumbled, swap Row and Col wires.
4. Replace SECRET_UID in code with your actual card UID.
   To find your UID: Check Serial Monitor output when scanning.
