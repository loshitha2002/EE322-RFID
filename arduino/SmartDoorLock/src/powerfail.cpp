#include "powerfail.h"

#include "config.h"

namespace {
volatile bool g_powerFailLatched = false;

void isrPowerFail() {
  g_powerFailLatched = true;
}
}

void initPowerFail() {
  pinMode(PIN_PWR_FAIL, INPUT_PULLUP);

  // Active-low power fail input: falling edge means power is going away.
  attachInterrupt(digitalPinToInterrupt(PIN_PWR_FAIL), isrPowerFail, FALLING);
}

bool takePowerFailEvent() {
  noInterrupts();
  bool v = g_powerFailLatched;
  g_powerFailLatched = false;
  interrupts();
  return v;
}

void powerFailPoll() {
  // Optional: if you later move away from interrupts.
}
