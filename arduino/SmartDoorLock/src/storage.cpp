#include "storage.h"
#include <EEPROM.h>

static uint8_t checksum8(const PersistedState& st) {
  // Simple checksum (exclude checksum field itself)
  return (uint8_t)(st.magic ^ st.lockState ^ st.wrongAttempts ^ st.lockoutSeconds);
}

void initStorage() {
  // Nothing required for EEPROM lib
}

PersistedState loadState() {
  PersistedState st{};
  EEPROM.get(0, st);
  if (st.magic != 0xA5) {
    st.magic = 0xA5;
    st.lockState = 0;
    st.wrongAttempts = 0;
    st.lockoutSeconds = 0;
    st.checksum = checksum8(st);
    EEPROM.put(0, st);
    return st;
  }
  if (st.checksum != checksum8(st)) {
    st.lockState = 0;
    st.wrongAttempts = 0;
    st.lockoutSeconds = 0;
    st.checksum = checksum8(st);
    EEPROM.put(0, st);
  }
  return st;
}

void saveState(const PersistedState& stIn) {
  PersistedState st = stIn;
  st.magic = 0xA5;
  st.checksum = checksum8(st);
  EEPROM.put(0, st);
}
