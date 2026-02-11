// TwoFactorLock_Pure.ino
// Pure C++ Implementation for Hardware Demo
// Hardware: Keypad (4x4), I2C LCD (16x2), MFRC522 RFID, LED, Buzzer

#include <Wire.h>
#include <LiquidCrystal_I2C.h> 
#include <Keypad.h>            
#include <SPI.h>
#include <MFRC522.h>

// ----- Hardware Configuration -----
#define PIN_BUZZER  8
#define PIN_LOCK    7
#define PIN_LED     A3

// LCD (Addr 0x27 is common)
LiquidCrystal_I2C lcd(0x27, 16, 2);

// RFID
#define SS_PIN 10
#define RST_PIN 9
MFRC522 rfid(SS_PIN, RST_PIN);

// Keypad
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

// ----- Secrets -----
const char* SECRET_PIN = "1234";
const uint8_t SECRET_UID[4] = {0xDE, 0xAD, 0xBE, 0xEF};

// ----- State Machine -----
enum State {
  IDLE,
  ENTER_PIN,
  CHECK_PIN,
  WAIT_RFID,
  ACCESS_GRANTED,
  ACCESS_DENIED
};

State currentState = IDLE;
char inputBuffer[10];
byte inputIndex = 0;

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LOCK, OUTPUT);
  pinMode(PIN_LED, OUTPUT);
  
  lcd.init();
  lcd.backlight();
  lcd.print("System Booting");
  
  SPI.begin();
  rfid.PCD_Init();
  
  delay(1000);
  resetSystem();
}

void loop() {
  switch (currentState) {
    case IDLE:
      if (keypad.getKey()) {
        resetSystem();
        lcd.clear();
        lcd.print("Enter PIN:");
        lcd.setCursor(0, 1);
        currentState = ENTER_PIN;
      }
      break;
      
    case ENTER_PIN:
      handlePinEntry();
      break;
      
    case CHECK_PIN:
      lcd.clear();
      lcd.print("Verifying...");
      delay(500);
      
      if (strcmp(inputBuffer, SECRET_PIN) == 0) {
        lcd.clear();
        lcd.print("PIN OK! Scan Card");
        tone(PIN_BUZZER, 2000, 100);
        currentState = WAIT_RFID;
      } else {
        lcd.clear();
        lcd.print("Wrong PIN!");
        tone(PIN_BUZZER, 500, 500);
        delay(2000);
        resetSystem();
      }
      break;
      
    case WAIT_RFID:
      handleRfidCheck();
      break;
      
    case ACCESS_GRANTED:
      lcd.clear();
      lcd.print("ACCESS GRANTED");
      digitalWrite(PIN_LOCK, HIGH);
      digitalWrite(PIN_LED, HIGH);
      tone(PIN_BUZZER, 3000, 200);
      delay(3000);
      
      digitalWrite(PIN_LOCK, LOW);
      digitalWrite(PIN_LED, LOW);
      resetSystem();
      break;
  }
}

void resetSystem() {
  lcd.clear();
  lcd.print("READY. Press Key");
  currentState = IDLE;
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
      currentState = CHECK_PIN;
    } else if (key == '*') {
      resetSystem();
    } else {
      if (inputIndex < 4) {
        inputBuffer[inputIndex] = key;
        inputIndex++;
        inputBuffer[inputIndex] = '\0';
        lcd.print('*');
      }
    }
  }
}

void handleRfidCheck() {
  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial()) return;
  
  lcd.clear();
  lcd.print("Reading Card...");
  
  bool match = true;
  for (byte i=0; i<4; i++) {
    if (rfid.uid.uidByte[i] != SECRET_UID[i]) match = false;
  }
  
  if (match) {
    currentState = ACCESS_GRANTED;
  } else {
    lcd.clear();
    lcd.print("Unknown Card");
    tone(PIN_BUZZER, 500, 1000);
    delay(2000);
    resetSystem();
  }
  
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}
