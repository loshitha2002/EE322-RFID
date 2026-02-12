// TwoFactorLock_Pure.ino
// Hardware: 4x4 Keypad + I2C LCD (16x2) + MFRC522 + Buzzer + Lock + LED
// Feature: 3 Wrong PIN attempts = 30 second lockout

#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Keypad.h>
#include <SPI.h>
#include <MFRC522.h>

// ------------------- Pin Configuration -------------------
#define PIN_BUZZER  8
#define PIN_LOCK    7
#define PIN_LED     A3

// LCD (Change address if needed: 0x27 or 0x3F)
LiquidCrystal_I2C lcd(0x27, 16, 2);

// RFID
#define SS_PIN 10
#define RST_PIN 9
MFRC522 rfid(SS_PIN, RST_PIN);

// ------------------- Keypad -------------------
const byte ROWS = 4;
const byte COLS = 4;

char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};

byte rowPins[ROWS] = {2, 3, 4, 5};
byte colPins[COLS] = {6, A0, A1, A2};

Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// ------------------- Secret Data -------------------
const char SECRET_PIN[] = "1234";

// Change this to your card UID
const byte SECRET_UID[4] = {0x67, 0x93, 0xA9, 0x04};

// ------------------- Security Settings -------------------
#define MAX_ATTEMPTS    3
#define LOCKOUT_TIME    30000  // 30 seconds in milliseconds

byte wrongAttempts = 0;
bool isLockedOut = false;
unsigned long lockoutStartTime = 0;

// ------------------- State Machine -------------------
enum SystemState {
  SYS_IDLE,
  SYS_ENTER_PIN,
  SYS_CHECK_PIN,
  SYS_WAIT_RFID,
  SYS_ACCESS_GRANTED,
  SYS_LOCKOUT
};

SystemState currentState = SYS_IDLE;

char inputBuffer[5];
byte inputIndex = 0;

// =======================================================
// ====================== SETUP ==========================
// =======================================================
void setup() {

  Serial.begin(115200);

  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LOCK, OUTPUT);
  pinMode(PIN_LED, OUTPUT);

  Wire.begin();
  lcd.init();
  delay(200);
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Booting");

  delay(1000);

  SPI.begin();
  rfid.PCD_Init();

  delay(1500);
  resetSystem();
}

// =======================================================
// ======================= LOOP ==========================
// =======================================================
void loop() {

  switch (currentState) {

    case SYS_IDLE: {
      char key = keypad.getKey();
      if (key) {
        lcd.clear();
        lcd.print("Enter PIN:");
        lcd.setCursor(0, 1);
        currentState = SYS_ENTER_PIN;

        // Save the first key press
        if (key != '#' && key != '*') {
          inputBuffer[inputIndex++] = key;
          inputBuffer[inputIndex] = '\0';
          lcd.print('*');
          tone(PIN_BUZZER, 1000, 50);
        }
        else if (key == '*') {
          resetSystem();
        }
      }
      break;
    }

    case SYS_ENTER_PIN:
      handlePinEntry();
      break;

    case SYS_CHECK_PIN:
      verifyPin();
      break;

    case SYS_WAIT_RFID:
      handleRfidCheck();
      break;

    case SYS_ACCESS_GRANTED:
      grantAccess();
      break;

    case SYS_LOCKOUT:
      handleLockout();
      break;
  }
}

// =======================================================
// ===================== FUNCTIONS =======================
// =======================================================

void resetSystem() {
  lcd.clear();
  lcd.print("READY. Press Key");

  if (wrongAttempts > 0) {
    lcd.setCursor(0, 1);
    lcd.print("Tries: ");
    lcd.print(MAX_ATTEMPTS - wrongAttempts);
    lcd.print(" left");
  }

  currentState = SYS_IDLE;
  inputIndex = 0;
  memset(inputBuffer, 0, sizeof(inputBuffer));
  digitalWrite(PIN_LOCK, LOW);
  digitalWrite(PIN_LED, LOW);
}

void handlePinEntry() {

  char key = keypad.getKey();

  if (key) {
    tone(PIN_BUZZER, 1000, 50);

    if (key == '#') {
      currentState = SYS_CHECK_PIN;
    }
    else if (key == '*') {
      resetSystem();
    }
    else {
      if (inputIndex < 4) {
        inputBuffer[inputIndex++] = key;
        inputBuffer[inputIndex] = '\0';
        lcd.print('*');
      }
    }
  }
}

void verifyPin() {

  lcd.clear();
  lcd.print("Verifying...");
  delay(800);

  if (strcmp(inputBuffer, SECRET_PIN) == 0) {

    // PIN correct - reset wrong attempts
    wrongAttempts = 0;

    lcd.clear();
    lcd.print("PIN OK!");
    lcd.setCursor(0, 1);
    lcd.print("Scan Card");
    tone(PIN_BUZZER, 2000, 150);

    currentState = SYS_WAIT_RFID;
  }
  else {
    // PIN wrong - increase attempt counter
    wrongAttempts++;

    lcd.clear();
    lcd.print("Wrong PIN!");
    lcd.setCursor(0, 1);

    if (wrongAttempts >= MAX_ATTEMPTS) {
      // LOCKOUT!
      lcd.print("SYSTEM LOCKED!");
      tone(PIN_BUZZER, 300, 2000);
      delay(2000);
      startLockout();
    }
    else {
      lcd.print("Tries left: ");
      lcd.print(MAX_ATTEMPTS - wrongAttempts);
      tone(PIN_BUZZER, 500, 700);
      delay(2000);
      resetSystem();
    }
  }
}

void startLockout() {
  isLockedOut = true;
  lockoutStartTime = millis();
  currentState = SYS_LOCKOUT;

  Serial.println(F("!!! SYSTEM LOCKED FOR 30 SECONDS !!!"));
}

void handleLockout() {

  unsigned long elapsed = millis() - lockoutStartTime;
  unsigned long remaining = 0;

  if (elapsed < LOCKOUT_TIME) {
    remaining = (LOCKOUT_TIME - elapsed) / 1000;
  }

  // Update countdown on LCD
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("!! LOCKED OUT !!");
  lcd.setCursor(0, 1);
  lcd.print("Wait: ");
  lcd.print(remaining);
  lcd.print("s");

  // Alarm beep every 2 seconds
  tone(PIN_BUZZER, 300, 200);

  // Ignore ALL keypad presses during lockout
  keypad.getKey();  // Read and throw away

  // Check if lockout is over
  if (elapsed >= LOCKOUT_TIME) {
    isLockedOut = false;
    wrongAttempts = 0;

    lcd.clear();
    lcd.print("Lock Released");
    tone(PIN_BUZZER, 2000, 200);
    delay(1500);

    resetSystem();
    return;
  }

  delay(1000);  // Update every 1 second
}

void handleRfidCheck() {

  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial()) return;

  lcd.clear();
  lcd.print("Reading Card...");

  bool match = true;

  for (byte i = 0; i < 4; i++) {
    if (rfid.uid.uidByte[i] != SECRET_UID[i]) {
      match = false;
    }
  }

  if (match) {
    currentState = SYS_ACCESS_GRANTED;
  }
  else {
    lcd.clear();
    lcd.print("Unknown Card!");
    tone(PIN_BUZZER, 400, 1000);
    delay(2000);
    resetSystem();
  }

  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

void grantAccess() {

  lcd.clear();
  lcd.print("ACCESS GRANTED");
  digitalWrite(PIN_LOCK, HIGH);
  digitalWrite(PIN_LED, HIGH);
  tone(PIN_BUZZER, 3000, 200);

  delay(3000);

  digitalWrite(PIN_LOCK, LOW);
  digitalWrite(PIN_LED, LOW);

  // Reset everything including attempts
  wrongAttempts = 0;
  resetSystem();
}