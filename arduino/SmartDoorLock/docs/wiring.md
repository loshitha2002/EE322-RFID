# Wiring (Draft)

Update this file with your actual wiring.

- Buzzer: PIN_BUZZER
- Lock actuator driver: PIN_LOCK_ACTUATOR
- Status LED: LED_BUILTIN
- RFID (MFRC522 SPI):
	- VCC -> 3.3V (do NOT use 5V)
	- GND -> GND
	- RST -> D9 (PIN_RFID_RST)
	- SDA / SS -> D10 (PIN_RFID_SS)
	- MOSI -> D11
	- MISO -> D12
	- SCK -> D13
- Power-fail detect: TBD (ADC or interrupt pin)

## Proteus simulation notes

Proteus typically does not include a real MFRC522 RFID model.

If you're simulating, enable `RFID_SIM_SERIAL` in `src/config.h` and use a Virtual Terminal:
- Set baud to `115200`
- Type a UID like `04:AB:10:9F` then press Enter

Power-fail simulation:
- Drive `PIN_PWR_FAIL` (D2) LOW to trigger a save-to-EEPROM event.
