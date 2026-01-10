#pragma once

#include <Arduino.h>

void initRfid();

// Returns true if a complete tag ID is available.
bool rfidTagAvailable();

// Copies tag ID bytes into outBuf (up to outMax). Returns number of bytes copied.
size_t rfidReadTag(uint8_t* outBuf, size_t outMax);
