#pragma once

#include <Arduino.h>

void initPowerFail();

// Returns true if a power-fail event was latched since last call.
bool takePowerFailEvent();

// Call periodically from loop() to check supply health (optional fallback).
void powerFailPoll();
