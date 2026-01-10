#pragma once

#include <Arduino.h>

// ----- Build options -----
// If you're simulating in Proteus and don't have an MFRC522 model, enable this.
// Then you can type a UID into a Virtual Terminal (Serial) to simulate a tag.
// Format: 4 bytes hex with ':' separators, e.g. 04:AB:10:9F
#define RFID_SIM_SERIAL 1

// Pin mapping (adjust to your wiring)
constexpr uint8_t PIN_BUZZER = 8;
constexpr uint8_t PIN_LOCK_ACTUATOR = 7;
constexpr uint8_t PIN_STATUS_LED = LED_BUILTIN;

// Power-fail detect input (use INT0 so attachInterrupt works on Uno/Nano)
// In Proteus you can toggle this pin LOW to simulate power loss event.
constexpr uint8_t PIN_PWR_FAIL = 2;

// MFRC522 (SPI) wiring (Arduino Uno/Nano default SPI pins are fixed)
// SCK  -> D13
// MISO -> D12
// MOSI -> D11
// SDA/SS -> choose a digital pin (commonly D10)
// RST -> choose a digital pin (commonly D9)
constexpr uint8_t PIN_RFID_SS = 10;
constexpr uint8_t PIN_RFID_RST = 9;

// Security parameters
constexpr uint8_t MAX_WRONG_ATTEMPTS = 3;
constexpr uint16_t LOCKOUT_SECONDS = 30;

void initConfig();
