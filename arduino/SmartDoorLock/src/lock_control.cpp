#include "lock_control.h"
#include "config.h"

void initLockControl() {
  pinMode(PIN_LOCK_ACTUATOR, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_STATUS_LED, OUTPUT);

  lockDoor();
}

void lockDoor() {
  digitalWrite(PIN_LOCK_ACTUATOR, LOW);
  digitalWrite(PIN_STATUS_LED, LOW);
}

void unlockDoor() {
  digitalWrite(PIN_LOCK_ACTUATOR, HIGH);
  digitalWrite(PIN_STATUS_LED, HIGH);
}
