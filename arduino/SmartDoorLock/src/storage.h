#pragma once

#include <Arduino.h>

struct PersistedState {
  uint8_t magic;
  uint8_t lockState;      // 0 = locked, 1 = unlocked
  uint8_t wrongAttempts;
  uint8_t lockoutSeconds; // remaining
  uint8_t checksum;
};

void initStorage();
PersistedState loadState();
void saveState(const PersistedState& st);
