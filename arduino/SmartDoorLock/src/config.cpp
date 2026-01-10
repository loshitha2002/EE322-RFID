#include "config.h"

void initConfig() {
  // Central place for any global init (Serial, etc.)
  Serial.begin(115200);
  while (!Serial) {
    // Wait for Serial on boards that require it (harmless on Uno/Nano)
  }
}
