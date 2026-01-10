#include "rfid.h"

#include <Arduino.h>

#include "config.h"

#if defined(RFID_SIM_SERIAL)

namespace {
uint8_t lastUid[10] = {0};
size_t lastUidLen = 0;
bool uidReady = false;

String g_lineBuf;

int hexVal(int c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
  if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
  return -1;
}

bool tryParseUidLine(const String& line) {
  // Expect 4 bytes like 04:AB:10:9F (whitespace allowed)
  uint8_t bytes[10];
  size_t count = 0;

  int hi = -1;
  for (size_t i = 0; i < line.length(); i++) {
    int v = hexVal(line[i]);
    if (v < 0) {
      continue;
    }
    if (hi < 0) {
      hi = v;
    } else {
      if (count >= sizeof(bytes)) {
        return false;
      }
      bytes[count++] = (uint8_t)((hi << 4) | v);
      hi = -1;
    }
  }

  if (count < 4) {
    return false;
  }
  lastUidLen = 4;  // keep it simple for bring-up
  for (size_t i = 0; i < lastUidLen; i++) {
    lastUid[i] = bytes[i];
  }
  uidReady = true;
  return true;
}
}

void initRfid() {
  // Nothing special: uses Serial (Virtual Terminal in Proteus)
  Serial.println("RFID sim mode: type UID like 04:AB:10:9F");
}

bool rfidTagAvailable() {
  if (uidReady) {
    return true;
  }

  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\r' || c == '\n') {
      String line = g_lineBuf;
      g_lineBuf = "";
      line.trim();
      if (line.length() == 0) {
        continue;
      }
      return tryParseUidLine(line);
    }
    g_lineBuf += c;
    if (g_lineBuf.length() > 64) {
      // prevent runaway input
      g_lineBuf = "";
    }
  }

  return false;
}

size_t rfidReadTag(uint8_t* outBuf, size_t outMax) {
  if (!uidReady || outBuf == nullptr || outMax == 0) {
    return 0;
  }
  size_t n = (lastUidLen < outMax) ? lastUidLen : outMax;
  for (size_t i = 0; i < n; i++) {
    outBuf[i] = lastUid[i];
  }
  uidReady = false;
  return n;
}

#else

#include <SPI.h>

namespace {

// MFRC522 register map (subset)
constexpr uint8_t CommandReg = 0x01;
constexpr uint8_t ComIEnReg = 0x02;
constexpr uint8_t DivIEnReg = 0x03;
constexpr uint8_t ComIrqReg = 0x04;
constexpr uint8_t DivIrqReg = 0x05;
constexpr uint8_t ErrorReg = 0x06;
constexpr uint8_t FIFODataReg = 0x09;
constexpr uint8_t FIFOLevelReg = 0x0A;
constexpr uint8_t ControlReg = 0x0C;
constexpr uint8_t BitFramingReg = 0x0D;
constexpr uint8_t ModeReg = 0x11;
constexpr uint8_t TxModeReg = 0x12;
constexpr uint8_t RxModeReg = 0x13;
constexpr uint8_t TxControlReg = 0x14;
constexpr uint8_t TxASKReg = 0x15;
constexpr uint8_t TModeReg = 0x2A;
constexpr uint8_t TPrescalerReg = 0x2B;
constexpr uint8_t TReloadRegH = 0x2C;
constexpr uint8_t TReloadRegL = 0x2D;
constexpr uint8_t VersionReg = 0x37;
constexpr uint8_t CRCResultRegH = 0x21;
constexpr uint8_t CRCResultRegL = 0x22;

// MFRC522 commands
constexpr uint8_t PCD_Idle = 0x00;
constexpr uint8_t PCD_Mem = 0x01;
constexpr uint8_t PCD_CalcCRC = 0x03;
constexpr uint8_t PCD_Transceive = 0x0C;
constexpr uint8_t PCD_SoftReset = 0x0F;

// PICC commands
constexpr uint8_t PICC_CMD_REQA = 0x26;
constexpr uint8_t PICC_CMD_SEL_CL1 = 0x93;

SPISettings spiSettings(4000000, MSBFIRST, SPI_MODE0);

uint8_t lastUid[10] = {0};
size_t lastUidLen = 0;
bool uidReady = false;

void selectChip(bool selected) {
  digitalWrite(PIN_RFID_SS, selected ? LOW : HIGH);
}

void writeReg(uint8_t reg, uint8_t value) {
  // Address format: 0XXXXXX0 (write)
  SPI.beginTransaction(spiSettings);
  selectChip(true);
  SPI.transfer((reg << 1) & 0x7E);
  SPI.transfer(value);
  selectChip(false);
  SPI.endTransaction();
}

uint8_t readReg(uint8_t reg) {
  // Address format: 1XXXXXX0 (read)
  SPI.beginTransaction(spiSettings);
  selectChip(true);
  SPI.transfer(((reg << 1) & 0x7E) | 0x80);
  uint8_t val = SPI.transfer(0x00);
  selectChip(false);
  SPI.endTransaction();
  return val;
}

void setBitMask(uint8_t reg, uint8_t mask) {
  writeReg(reg, readReg(reg) | mask);
}

void clearBitMask(uint8_t reg, uint8_t mask) {
  writeReg(reg, readReg(reg) & (~mask));
}

void antennaOn() {
  uint8_t v = readReg(TxControlReg);
  if ((v & 0x03) != 0x03) {
    setBitMask(TxControlReg, 0x03);
  }
}

bool calcCrcA(const uint8_t* data, size_t len, uint8_t* outCrc2) {
  writeReg(CommandReg, PCD_Idle);
  writeReg(DivIrqReg, 0x04);
  writeReg(FIFOLevelReg, 0x80);

  for (size_t i = 0; i < len; i++) {
    writeReg(FIFODataReg, data[i]);
  }

  writeReg(CommandReg, PCD_CalcCRC);

  const uint32_t start = millis();
  while (true) {
    uint8_t n = readReg(DivIrqReg);
    if (n & 0x04) {
      break;
    }
    if (millis() - start > 20) {
      writeReg(CommandReg, PCD_Idle);
      return false;
    }
  }

  outCrc2[0] = readReg(CRCResultRegL);
  outCrc2[1] = readReg(CRCResultRegH);
  return true;
}

// Transceive data; returns true on success, fills backData/backBits.
bool transceive(const uint8_t* sendData,
                size_t sendLen,
                uint8_t* backData,
                size_t* backLen,
                uint8_t* backBits) {
  writeReg(CommandReg, PCD_Idle);
  writeReg(ComIrqReg, 0x7F);
  writeReg(FIFOLevelReg, 0x80);
  for (size_t i = 0; i < sendLen; i++) {
    writeReg(FIFODataReg, sendData[i]);
  }

  writeReg(CommandReg, PCD_Transceive);
  setBitMask(BitFramingReg, 0x80);  // StartSend

  // Wait for RX or idle
  const uint32_t start = millis();
  while (true) {
    uint8_t n = readReg(ComIrqReg);
    if (n & 0x30) {  // RxIRq or IdleIRq
      break;
    }
    if (millis() - start > 50) {
      clearBitMask(BitFramingReg, 0x80);
      writeReg(CommandReg, PCD_Idle);
      return false;
    }
  }

  clearBitMask(BitFramingReg, 0x80);

  uint8_t error = readReg(ErrorReg);
  if (error & 0x13) {  // BufferOvfl | ParityErr | ProtocolErr
    return false;
  }

  uint8_t n = readReg(FIFOLevelReg);
  if (n > *backLen) {
    return false;
  }
  *backLen = n;

  for (uint8_t i = 0; i < n; i++) {
    backData[i] = readReg(FIFODataReg);
  }

  uint8_t validBits = readReg(ControlReg) & 0x07;
  if (backBits) {
    *backBits = validBits;
  }
  return true;
}

bool requestA() {
  // REQA is 7 bits
  writeReg(BitFramingReg, 0x07);
  uint8_t cmd = PICC_CMD_REQA;
  uint8_t back[2] = {0};
  size_t backLen = sizeof(back);
  uint8_t backBits = 0;
  bool ok = transceive(&cmd, 1, back, &backLen, &backBits);
  // Expect ATQA: 2 bytes, and validBits should be 0
  return ok && backLen == 2;
}

bool anticollCl1(uint8_t* outUid5) {
  // Anticollision: SEL + NVB
  writeReg(BitFramingReg, 0x00);
  uint8_t send[2] = {PICC_CMD_SEL_CL1, 0x20};
  uint8_t back[10] = {0};
  size_t backLen = sizeof(back);
  uint8_t backBits = 0;
  if (!transceive(send, sizeof(send), back, &backLen, &backBits)) {
    return false;
  }
  if (backLen != 5) {
    return false;
  }
  // UID0..UID3 + BCC
  for (size_t i = 0; i < 5; i++) {
    outUid5[i] = back[i];
  }
  uint8_t bcc = outUid5[0] ^ outUid5[1] ^ outUid5[2] ^ outUid5[3];
  return (bcc == outUid5[4]);
}

}  // namespace

void initRfid() {
  pinMode(PIN_RFID_SS, OUTPUT);
  pinMode(PIN_RFID_RST, OUTPUT);
  digitalWrite(PIN_RFID_SS, HIGH);
  digitalWrite(PIN_RFID_RST, HIGH);

  SPI.begin();

  // Reset pulse
  digitalWrite(PIN_RFID_RST, LOW);
  delay(50);
  digitalWrite(PIN_RFID_RST, HIGH);
  delay(50);

  writeReg(CommandReg, PCD_SoftReset);
  delay(50);

  // Recommended timer / modulation setup (based on common MFRC522 init sequences)
  writeReg(TModeReg, 0x8D);
  writeReg(TPrescalerReg, 0x3E);
  writeReg(TReloadRegL, 30);
  writeReg(TReloadRegH, 0);
  writeReg(TxASKReg, 0x40);
  writeReg(ModeReg, 0x3D);
  writeReg(TxModeReg, 0x00);
  writeReg(RxModeReg, 0x00);

  antennaOn();

  uint8_t ver = readReg(VersionReg);
  Serial.print("MFRC522 VersionReg=0x");
  Serial.println(ver, HEX);
}

bool rfidTagAvailable() {
  if (uidReady) {
    return true;
  }

  if (!requestA()) {
    return false;
  }

  uint8_t uid5[5] = {0};
  if (!anticollCl1(uid5)) {
    return false;
  }

  // Store UID (4 bytes) for now (single cascade level only)
  lastUidLen = 4;
  for (size_t i = 0; i < 4; i++) {
    lastUid[i] = uid5[i];
  }
  uidReady = true;
  return true;
}

size_t rfidReadTag(uint8_t* outBuf, size_t outMax) {
  if (!uidReady || outBuf == nullptr || outMax == 0) {
    return 0;
  }
  size_t n = (lastUidLen < outMax) ? lastUidLen : outMax;
  for (size_t i = 0; i < n; i++) {
    outBuf[i] = lastUid[i];
  }
  uidReady = false;
  return n;
}

#endif
