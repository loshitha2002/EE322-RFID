// ============================================================================
// TwoFactorLock_Hybrid.ino
// HYBRID VERSION: C++ Libraries + Inline AVR Assembly
//
// Strategy:
//   - C++ Libraries handle complex protocols (I2C LCD, SPI RFID, Keypad matrix)
//   - Inline Assembly handles ALL GPIO, logic, and control operations
//
// Hardware: ATmega328P @ 16MHz
//   4x4 Keypad + I2C LCD (16x2) + MFRC522 RFID + Buzzer + Lock + LED
// Feature: 3 Wrong PIN attempts = 30 second lockout
// ============================================================================

#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Keypad.h>
#include <SPI.h>
#include <MFRC522.h>

// ============================================================================
// PIN CONFIGURATION (AVR register mapping)
// ============================================================================
// PIN_BUZZER  = D8  = PB0   (PORTB bit 0)
// PIN_LOCK    = D7  = PD7   (PORTD bit 7)
// PIN_LED     = A3  = PC3   (PORTC bit 3)
// RFID SS     = D10 = PB2
// RFID RST    = D9  = PB1

// ============================================================================
// C++ LIBRARY OBJECTS (complex protocol handlers)
// ============================================================================
LiquidCrystal_I2C lcd(0x27, 16, 2);
MFRC522 rfid(10, 9);  // SS=D10, RST=D9

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

// ============================================================================
// SECRET DATA
// ============================================================================
const char SECRET_PIN[] = "1234";
const byte SECRET_UID[4] = {0x67, 0x93, 0xA9, 0x04};  // Blue tag

// ============================================================================
// STATE VARIABLES
// ============================================================================
#define MAX_ATTEMPTS   3
#define LOCKOUT_TIME   30000UL  // 30 seconds

volatile byte wrongAttempts = 0;
volatile byte isLockedOut   = 0;
unsigned long lockoutStartTime = 0;

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

// ============================================================================
// ====================== INLINE ASSEMBLY FUNCTIONS ==========================
// ============================================================================

// ----------------------------------------------------------------------------
// ASM: Initialize output pins (Buzzer=PB0, Lock=PD7, LED=PC3)
//      Sets DDR bits to 1 (output), clears PORT bits to 0 (off)
// ----------------------------------------------------------------------------
void asm_init_pins() {
  asm volatile(
    // DDRB |= (1 << PB0)  -- Buzzer output
    "sbi  0x04, 0       \n\t"   // DDRB bit 0 = 1
    "cbi  0x05, 0       \n\t"   // PORTB bit 0 = 0 (buzzer off)

    // DDRD |= (1 << PD7)  -- Lock output
    "sbi  0x0A, 7       \n\t"   // DDRD bit 7 = 1
    "cbi  0x0B, 7       \n\t"   // PORTD bit 7 = 0 (lock off)

    // DDRC |= (1 << PC3)  -- LED output
    "sbi  0x07, 3       \n\t"   // DDRC bit 3 = 1
    "cbi  0x08, 3       \n\t"   // PORTC bit 3 = 0 (LED off)
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: LED ON  -- set PC3 high
// ----------------------------------------------------------------------------
void asm_led_on() {
  asm volatile(
    "sbi  0x08, 3  \n\t"       // PORTC bit 3 = 1
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: LED OFF -- clear PC3 low
// ----------------------------------------------------------------------------
void asm_led_off() {
  asm volatile(
    "cbi  0x08, 3  \n\t"       // PORTC bit 3 = 0
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Buzzer ON  -- set PB0 high
// ----------------------------------------------------------------------------
void asm_buzzer_on() {
  asm volatile(
    "sbi  0x05, 0  \n\t"       // PORTB bit 0 = 1
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Buzzer OFF -- clear PB0 low
// ----------------------------------------------------------------------------
void asm_buzzer_off() {
  asm volatile(
    "cbi  0x05, 0  \n\t"       // PORTB bit 0 = 0
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Lock ON (unlock the door) -- set PD7 high
// ----------------------------------------------------------------------------
void asm_lock_on() {
  asm volatile(
    "sbi  0x0B, 7  \n\t"       // PORTD bit 7 = 1
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Lock OFF (lock the door) -- clear PD7 low
// ----------------------------------------------------------------------------
void asm_lock_off() {
  asm volatile(
    "cbi  0x0B, 7  \n\t"       // PORTD bit 7 = 0
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Short Beep (50ms) -- buzzer on, delay, buzzer off
//      Uses nested delay loops calibrated for 16MHz
// ----------------------------------------------------------------------------
void asm_beep_short() {
  asm volatile(
    "sbi  0x05, 0       \n\t"   // Buzzer ON (PORTB bit 0)

    // ~50ms delay at 16MHz:  outer * inner * 3 cycles ≈ 800,000 cycles
    // 200 * 1333 * 3 = 799,800 ≈ 50ms
    "ldi  r18, 200      \n\t"   // outer loop
  "beep_outer_%=:        \n\t"
    "ldi  r24, lo8(1333) \n\t"  // inner loop low
    "ldi  r25, hi8(1333) \n\t"  // inner loop high
  "beep_inner_%=:        \n\t"
    "sbiw r24, 1        \n\t"   // 2 cycles
    "brne beep_inner_%=  \n\t"  // 1/2 cycles
    "dec  r18            \n\t"
    "brne beep_outer_%=  \n\t"

    "cbi  0x05, 0       \n\t"   // Buzzer OFF
    ::: "r18", "r24", "r25", "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Long Beep (500ms) -- for alarm/error
// ----------------------------------------------------------------------------
void asm_beep_long() {
  asm volatile(
    "sbi  0x05, 0       \n\t"   // Buzzer ON

    // ~500ms delay: 250 * 10666 * 3 ≈ 8,000,000 cycles = 500ms @ 16MHz
    "ldi  r18, 250      \n\t"
  "blong_outer_%=:       \n\t"
    "ldi  r24, lo8(10666)\n\t"
    "ldi  r25, hi8(10666)\n\t"
  "blong_inner_%=:       \n\t"
    "sbiw r24, 1        \n\t"
    "brne blong_inner_%=\n\t"
    "dec  r18            \n\t"
    "brne blong_outer_%=\n\t"

    "cbi  0x05, 0       \n\t"   // Buzzer OFF
    ::: "r18", "r24", "r25", "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Alarm Beep (200ms) -- for lockout warning
// ----------------------------------------------------------------------------
void asm_beep_alarm() {
  asm volatile(
    "sbi  0x05, 0       \n\t"   // Buzzer ON

    // ~200ms delay: 200 * 5333 * 3 ≈ 3,200,000 cycles = 200ms @ 16MHz
    "ldi  r18, 200      \n\t"
  "balarm_outer_%=:      \n\t"
    "ldi  r24, lo8(5333) \n\t"
    "ldi  r25, hi8(5333) \n\t"
  "balarm_inner_%=:      \n\t"
    "sbiw r24, 1        \n\t"
    "brne balarm_inner_%=\n\t"
    "dec  r18            \n\t"
    "brne balarm_outer_%=\n\t"

    "cbi  0x05, 0       \n\t"   // Buzzer OFF
    ::: "r18", "r24", "r25", "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Compare PIN -- byte-by-byte compare of 4-char PIN
//      Returns 1 if match, 0 if mismatch
// ----------------------------------------------------------------------------
uint8_t asm_compare_pin(const char* entered, const char* secret) {
  uint8_t result;
  asm volatile(
    // r30:r31 = Z = entered pointer
    // r26:r27 = X = secret pointer
    "movw  r30, %[ent]   \n\t"  // Z = entered
    "movw  r26, %[sec]   \n\t"  // X = secret
    "ldi   %[res], 1     \n\t"  // result = 1 (assume match)
    "ldi   r18, 4        \n\t"  // counter = 4 bytes

  "cmp_loop_%=:          \n\t"
    "ld    r19, Z+       \n\t"  // load entered[i]
    "ld    r20, X+       \n\t"  // load secret[i]
    "cpse  r19, r20      \n\t"  // skip next if equal
    "clr   %[res]        \n\t"  // mismatch: result = 0
    "dec   r18           \n\t"
    "brne  cmp_loop_%=   \n\t"

    : [res] "=&r" (result)
    : [ent] "r" (entered), [sec] "r" (secret)
    : "r18", "r19", "r20", "r26", "r27", "r30", "r31"
  );
  return result;
}

// ----------------------------------------------------------------------------
// ASM: Compare UID -- byte-by-byte compare of 4-byte RFID UID
//      Returns 1 if match, 0 if mismatch
// ----------------------------------------------------------------------------
uint8_t asm_compare_uid(const byte* scanned, const byte* secret) {
  uint8_t result;
  asm volatile(
    "movw  r30, %[scan]  \n\t"  // Z = scanned UID
    "movw  r26, %[sec]   \n\t"  // X = secret UID
    "ldi   %[res], 1     \n\t"  // result = 1 (assume match)
    "ldi   r18, 4        \n\t"  // counter = 4 bytes

  "uid_loop_%=:          \n\t"
    "ld    r19, Z+       \n\t"  // load scanned[i]
    "ld    r20, X+       \n\t"  // load secret[i]
    "cpse  r19, r20      \n\t"  // skip next if equal
    "clr   %[res]        \n\t"  // mismatch: result = 0
    "dec   r18           \n\t"
    "brne  uid_loop_%=   \n\t"

    : [res] "=&r" (result)
    : [scan] "r" (scanned), [sec] "r" (secret)
    : "r18", "r19", "r20", "r26", "r27", "r30", "r31"
  );
  return result;
}

// ----------------------------------------------------------------------------
// ASM: Clear input buffer -- zero out 5 bytes and reset index
// ----------------------------------------------------------------------------
void asm_clear_buffer() {
  asm volatile(
    "movw  r30, %[buf]   \n\t"  // Z = buffer pointer
    "clr   r18           \n\t"  // r18 = 0
    "st    Z+, r18       \n\t"  // buffer[0] = 0
    "st    Z+, r18       \n\t"  // buffer[1] = 0
    "st    Z+, r18       \n\t"  // buffer[2] = 0
    "st    Z+, r18       \n\t"  // buffer[3] = 0
    "st    Z,  r18       \n\t"  // buffer[4] = 0
    :
    : [buf] "r" (inputBuffer)
    : "r18", "r30", "r31", "memory"
  );
  inputIndex = 0;
}

// ----------------------------------------------------------------------------
// ASM: Increment wrong attempts -- load, increment, store, return new value
// ----------------------------------------------------------------------------
uint8_t asm_inc_wrong_attempts() {
  uint8_t val;
  asm volatile(
    "lds   %[v], %[addr] \n\t"  // load wrongAttempts
    "inc   %[v]          \n\t"  // increment
    "sts   %[addr], %[v] \n\t"  // store back
    : [v] "=&r" (val)
    : [addr] "i" (&wrongAttempts)
    : "memory"
  );
  return val;
}

// ----------------------------------------------------------------------------
// ASM: Reset wrong attempts -- store 0
// ----------------------------------------------------------------------------
void asm_reset_wrong_attempts() {
  asm volatile(
    "clr   r18           \n\t"
    "sts   %[addr], r18  \n\t"  // wrongAttempts = 0
    :
    : [addr] "i" (&wrongAttempts)
    : "r18", "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Get remaining tries -- returns (MAX_ATTEMPTS - wrongAttempts)
// ----------------------------------------------------------------------------
uint8_t asm_remaining_tries() {
  uint8_t result;
  asm volatile(
    "ldi   %[res], %[max]\n\t"  // result = MAX_ATTEMPTS
    "lds   r18, %[addr]  \n\t"  // r18 = wrongAttempts
    "sub   %[res], r18   \n\t"  // result = MAX - wrong
    : [res] "=&r" (result)
    : [max] "M" (MAX_ATTEMPTS), [addr] "i" (&wrongAttempts)
    : "r18"
  );
  return result;
}

// ----------------------------------------------------------------------------
// ASM: Check if lockout threshold reached
//      Returns 1 if wrongAttempts >= MAX_ATTEMPTS, else 0
// ----------------------------------------------------------------------------
uint8_t asm_check_lockout_threshold() {
  uint8_t result;
  asm volatile(
    "lds   r18, %[addr]  \n\t"  // r18 = wrongAttempts
    "cpi   r18, %[max]   \n\t"  // compare with MAX_ATTEMPTS
    "brsh  lockout_yes_%=\n\t"  // branch if >= MAX
    "clr   %[res]        \n\t"  // result = 0 (not locked)
    "rjmp  lockout_end_%=\n\t"
  "lockout_yes_%=:       \n\t"
    "ldi   %[res], 1     \n\t"  // result = 1 (lockout!)
  "lockout_end_%=:       \n\t"
    : [res] "=&r" (result)
    : [max] "M" (MAX_ATTEMPTS), [addr] "i" (&wrongAttempts)
    : "r18"
  );
  return result;
}

// ----------------------------------------------------------------------------
// ASM: Set lockout flag
// ----------------------------------------------------------------------------
void asm_set_lockout(uint8_t val) {
  asm volatile(
    "sts   %[addr], %[v] \n\t"
    :
    : [v] "r" (val), [addr] "i" (&isLockedOut)
    : "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: All outputs OFF -- clear Buzzer, Lock, LED simultaneously
// ----------------------------------------------------------------------------
void asm_all_off() {
  asm volatile(
    "cbi  0x05, 0       \n\t"   // Buzzer OFF  (PORTB bit 0)
    "cbi  0x0B, 7       \n\t"   // Lock OFF    (PORTD bit 7)
    "cbi  0x08, 3       \n\t"   // LED OFF     (PORTC bit 3)
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: All outputs ON -- set Buzzer, Lock, LED simultaneously
// ----------------------------------------------------------------------------
void asm_all_on() {
  asm volatile(
    "sbi  0x05, 0       \n\t"   // Buzzer ON   (PORTB bit 0)
    "sbi  0x0B, 7       \n\t"   // Lock ON     (PORTD bit 7)
    "sbi  0x08, 3       \n\t"   // LED ON      (PORTC bit 3)
    ::: "memory"
  );
}

// ----------------------------------------------------------------------------
// ASM: Read a pin state -- returns 1 if PB0 (buzzer pin) is high
//      (Example of reading PIN register)
// ----------------------------------------------------------------------------
uint8_t asm_read_buzzer_state() {
  uint8_t result;
  asm volatile(
    "clr   %[res]        \n\t"
    "sbic  0x03, 0       \n\t"  // skip if PINB bit 0 is clear
    "ldi   %[res], 1     \n\t"  // it's set, result = 1
    : [res] "=r" (result)
    :
    :
  );
  return result;
}

// ============================================================================
// ========================== SETUP (C++ + ASM) ==============================
// ============================================================================
void setup() {
  Serial.begin(115200);

  // --- ASM: Initialize GPIO pins ---
  asm_init_pins();

  // --- C++: Initialize I2C LCD (complex protocol) ---
  Wire.begin();
  lcd.init();
  delay(200);
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("System Booting");
  lcd.setCursor(0, 1);
  lcd.print("[Hybrid ASM+C]");

  delay(1000);

  // --- C++: Initialize SPI RFID (complex protocol) ---
  SPI.begin();
  rfid.PCD_Init();

  // --- ASM: Ensure all outputs are off at boot ---
  asm_all_off();

  // --- ASM: Reset security counters ---
  asm_reset_wrong_attempts();
  asm_set_lockout(0);

  delay(1500);
  resetSystem();
}

// ============================================================================
// ============================ MAIN LOOP ====================================
// ============================================================================
void loop() {
  switch (currentState) {

    case SYS_IDLE: {
      char key = keypad.getKey();  // C++: Keypad scanning
      if (key) {
        lcd.clear();
        lcd.print("Enter PIN:");
        lcd.setCursor(0, 1);
        currentState = SYS_ENTER_PIN;

        // Save first key if it's a digit
        if (key != '#' && key != '*') {
          inputBuffer[inputIndex++] = key;
          inputBuffer[inputIndex] = '\0';
          lcd.print('*');
          asm_beep_short();     // ASM: short beep feedback
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

// ============================================================================
// ========================= SYSTEM FUNCTIONS ================================
// ============================================================================

// --- Reset system to IDLE state ---
void resetSystem() {
  lcd.clear();                    // C++: LCD
  lcd.print("READY. Press Key");

  uint8_t remaining = asm_remaining_tries();  // ASM: calculate tries
  if (remaining < MAX_ATTEMPTS) {
    lcd.setCursor(0, 1);
    lcd.print("Tries: ");
    lcd.print(remaining);
    lcd.print(" left");
  }

  currentState = SYS_IDLE;
  asm_clear_buffer();             // ASM: zero the input buffer
  asm_lock_off();                 // ASM: lock the door
  asm_led_off();                  // ASM: LED off
}

// --- Handle PIN digit entry ---
void handlePinEntry() {
  char key = keypad.getKey();     // C++: Keypad scanning

  if (key) {
    asm_beep_short();             // ASM: key press beep

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
        lcd.print('*');           // C++: LCD feedback
      }
    }
  }
}

// --- Verify entered PIN using ASM compare ---
void verifyPin() {
  lcd.clear();
  lcd.print("Verifying...");
  delay(800);

  // *** ASM: Compare PIN byte-by-byte ***
  uint8_t pinMatch = asm_compare_pin(inputBuffer, SECRET_PIN);

  if (pinMatch) {
    // PIN correct
    asm_reset_wrong_attempts();   // ASM: reset counter

    lcd.clear();
    lcd.print("PIN OK!");
    lcd.setCursor(0, 1);
    lcd.print("Scan Card");
    asm_beep_short();             // ASM: success beep
    delay(100);
    asm_beep_short();             // ASM: double beep

    currentState = SYS_WAIT_RFID;
  }
  else {
    // PIN wrong
    uint8_t attempts = asm_inc_wrong_attempts();  // ASM: increment

    lcd.clear();
    lcd.print("Wrong PIN!");
    lcd.setCursor(0, 1);

    // *** ASM: Check if lockout threshold reached ***
    if (asm_check_lockout_threshold()) {
      lcd.print("SYSTEM LOCKED!");
      asm_beep_long();            // ASM: long alarm beep
      delay(1500);
      startLockout();
    }
    else {
      lcd.print("Tries left: ");
      lcd.print(asm_remaining_tries());  // ASM: remaining tries
      asm_beep_long();            // ASM: error beep
      delay(2000);
      resetSystem();
    }
  }
}

// --- Start 30-second lockout ---
void startLockout() {
  asm_set_lockout(1);             // ASM: set lockout flag
  lockoutStartTime = millis();
  currentState = SYS_LOCKOUT;

  Serial.println(F("!!! SYSTEM LOCKED FOR 30 SECONDS !!!"));
}

// --- Handle lockout countdown ---
void handleLockout() {
  unsigned long elapsed = millis() - lockoutStartTime;
  unsigned long remaining = 0;

  if (elapsed < LOCKOUT_TIME) {
    remaining = (LOCKOUT_TIME - elapsed) / 1000;
  }

  // C++: Update LCD countdown
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("!! LOCKED OUT !!");
  lcd.setCursor(0, 1);
  lcd.print("Wait: ");
  lcd.print(remaining);
  lcd.print("s");

  // ASM: Alarm beep
  asm_beep_alarm();

  // Drain keypad (ignore input during lockout)
  keypad.getKey();

  // Check if lockout is over
  if (elapsed >= LOCKOUT_TIME) {
    asm_set_lockout(0);           // ASM: clear lockout flag
    asm_reset_wrong_attempts();   // ASM: reset counter

    lcd.clear();
    lcd.print("Lock Released");
    asm_beep_short();
    delay(100);
    asm_beep_short();
    delay(1500);

    resetSystem();
    return;
  }

  delay(1000);  // Update every 1 second
}

// --- Handle RFID card scanning using ASM compare ---
void handleRfidCheck() {
  // C++: RFID card detection (complex SPI protocol)
  if (!rfid.PICC_IsNewCardPresent()) return;
  if (!rfid.PICC_ReadCardSerial()) return;

  lcd.clear();
  lcd.print("Reading Card...");

  // *** ASM: Compare UID byte-by-byte ***
  uint8_t uidMatch = asm_compare_uid(rfid.uid.uidByte, SECRET_UID);

  if (uidMatch) {
    currentState = SYS_ACCESS_GRANTED;
  }
  else {
    lcd.clear();
    lcd.print("Unknown Card!");
    asm_beep_long();              // ASM: rejection beep
    delay(2000);
    resetSystem();
  }

  // C++: Stop RFID communication
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
}

// --- Grant access: unlock door ---
void grantAccess() {
  lcd.clear();
  lcd.print("ACCESS GRANTED");

  // *** ASM: Activate lock and LED ***
  asm_lock_on();                  // ASM: unlock door (PD7 HIGH)
  asm_led_on();                   // ASM: LED on (PC3 HIGH)
  asm_beep_short();               // ASM: success beep
  delay(100);
  asm_beep_short();               // ASM: double beep
  delay(100);
  asm_beep_short();               // ASM: triple beep

  delay(3000);

  // *** ASM: Deactivate lock and LED ***
  asm_lock_off();                 // ASM: lock door (PD7 LOW)
  asm_led_off();                  // ASM: LED off (PC3 LOW)

  // ASM: Reset security counters
  asm_reset_wrong_attempts();

  resetSystem();
}

// ============================================================================
// END OF HYBRID VERSION
// ============================================================================
// Assembly functions used in this code:
//   asm_init_pins()              - GPIO DDR/PORT register setup
//   asm_led_on() / asm_led_off() - Direct SBI/CBI on PORTC
//   asm_buzzer_on() / off()      - Direct SBI/CBI on PORTB
//   asm_lock_on() / off()        - Direct SBI/CBI on PORTD
//   asm_beep_short()             - 50ms beep with delay loops
//   asm_beep_long()              - 500ms beep with delay loops
//   asm_beep_alarm()             - 200ms beep with delay loops
//   asm_compare_pin()            - 4-byte PIN comparison (LD, CPSE)
//   asm_compare_uid()            - 4-byte UID comparison (LD, CPSE)
//   asm_clear_buffer()           - Zero 5 bytes using ST
//   asm_inc_wrong_attempts()     - LDS, INC, STS on SRAM variable
//   asm_reset_wrong_attempts()   - CLR + STS
//   asm_remaining_tries()        - LDI, LDS, SUB arithmetic
//   asm_check_lockout_threshold()- LDS, CPI, BRSH conditional
//   asm_set_lockout()            - STS flag variable
//   asm_all_off() / all_on()     - Multiple SBI/CBI in sequence
//   asm_read_buzzer_state()      - SBIC/SBIS pin reading
// ============================================================================
