// SmartDoorLock.ino
// Arduino prototype for ATmega328P RFID door lock

#include "src/config.h"
#include "src/rfid.h"
#include "src/lock_control.h"
#include "src/powerfail.h"
#include "src/storage.h"

namespace {

// TODO: Replace with your actual authorized card UID (4 bytes).
// You can read it from Serial Monitor during bring-up.
const uint8_t AUTH_UID[4] = {0xDE, 0xAD, 0xBE, 0xEF};

PersistedState g_state{};

uint32_t g_lastSecondTickMs = 0;

bool uidMatchesAuthorized(const uint8_t* uid, size_t n) {
  if (n != 4) {
    return false;
  }
  for (size_t i = 0; i < 4; i++) {
    if (uid[i] != AUTH_UID[i]) {
      return false;
    }
  }
  return true;
}

void beep(uint16_t ms) {
  digitalWrite(PIN_BUZZER, HIGH);
  delay(ms);
  digitalWrite(PIN_BUZZER, LOW);
}

void applyLockState() {
  if (g_state.lockState) {
    unlockDoor();
  } else {
    lockDoor();
  }
}

}  // namespace

void setup() {
  initConfig();
  initLockControl();
  initStorage();
  initPowerFail();
  initRfid();

  g_state = loadState();
  applyLockState();

  Serial.print("Restored state: lockState=");
  Serial.print(g_state.lockState);
  Serial.print(" wrongAttempts=");
  Serial.print(g_state.wrongAttempts);
  Serial.print(" lockoutSeconds=");
  Serial.println(g_state.lockoutSeconds);

  g_lastSecondTickMs = millis();
}

void loop() {
  // If power-fail was detected, persist immediately.
  if (takePowerFailEvent()) {
    Serial.println("Power-fail event: saving EEPROM state");
    saveState(g_state);
    beep(150);
  }

  // 1-second tick for lockout countdown.
  const uint32_t now = millis();
  if (now - g_lastSecondTickMs >= 1000) {
    g_lastSecondTickMs += 1000;
    if (g_state.lockoutSeconds > 0) {
      g_state.lockoutSeconds--;
      // Simple lockout buzzer: short beep each second
      beep(40);
      if (g_state.lockoutSeconds == 0) {
        g_state.wrongAttempts = 0;
        Serial.println("Lockout ended");
        saveState(g_state);
      }
    }
  }

  // Check RFID
  if (rfidTagAvailable()) {
    uint8_t uid[10];
    size_t n = rfidReadTag(uid, sizeof(uid));
    if (n == 0) {
      return;
    }

    Serial.print("UID (");
    Serial.print(n);
    Serial.print(" bytes): ");
    for (size_t i = 0; i < n; i++) {
      if (uid[i] < 0x10) Serial.print('0');
      Serial.print(uid[i], HEX);
      if (i + 1 < n) Serial.print(':');
    }
    Serial.println();

    if (g_state.lockoutSeconds > 0) {
      Serial.println("Ignored (lockout active)");
      beep(80);
      delay(200);
      return;
    }

    if (uidMatchesAuthorized(uid, n)) {
      // Toggle lock state on authorized tag
      g_state.lockState = g_state.lockState ? 0 : 1;
      g_state.wrongAttempts = 0;
      applyLockState();
      saveState(g_state);
      Serial.println(g_state.lockState ? "Unlocked" : "Locked");
      beep(60);
      delay(250);
    } else {
      g_state.wrongAttempts++;
      Serial.print("Wrong attempt ");
      Serial.println(g_state.wrongAttempts);
      beep(120);

      if (g_state.wrongAttempts >= MAX_WRONG_ATTEMPTS) {
        g_state.lockState = 0;
        g_state.lockoutSeconds = LOCKOUT_SECONDS;
        applyLockState();
        saveState(g_state);
        Serial.println("LOCKOUT 30 seconds");
      } else {
        saveState(g_state);
      }

      delay(300);
    }
  }

  powerFailPoll();
}
