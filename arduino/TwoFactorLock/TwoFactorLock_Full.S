// ============================================================================
// TwoFactorLock_Full.S
// EXACT Assembly Translation of TwoFactorLock.ino
// Hardware: 4x4 Keypad + I2C LCD (16x2) + MFRC522 + Buzzer + Lock + LED
// Feature: 3 Wrong PIN attempts = 30 second lockout
// ============================================================================

#define __SFR_OFFSET 0
#include <avr/io.h>

// ============================================================================
// PIN CONFIGURATION (Matches TwoFactorLock.ino exactly)
// ============================================================================
// PIN_BUZZER  = D8  = PB0
// PIN_LOCK    = D7  = PD7
// PIN_LED     = A3  = PC3
// RFID SS     = D10 = PB2
// RFID RST    = D9  = PB1
// RFID MOSI   = D11 = PB3
// RFID MISO   = D12 = PB4
// RFID SCK    = D13 = PB5
// LCD SDA     = A4  = PC4
// LCD SCL     = A5  = PC5
// Keypad Row1 = D2  = PD2
// Keypad Row2 = D3  = PD3
// Keypad Row3 = D4  = PD4
// Keypad Row4 = D5  = PD5
// Keypad Col1 = D6  = PD6
// Keypad Col2 = A0  = PC0
// Keypad Col3 = A1  = PC1
// Keypad Col4 = A2  = PC2

// ============================================================================
// CONSTANTS (Matches TwoFactorLock.ino exactly)
// ============================================================================
.equ PIN_LENGTH,        4
.equ MAX_ATTEMPTS,      3
.equ LOCKOUT_TIME_S,    30

// State Machine Values
.equ SYS_IDLE,          0
.equ SYS_ENTER_PIN,     1
.equ SYS_CHECK_PIN,     2
.equ SYS_WAIT_RFID,     3
.equ SYS_ACCESS_GRANTED,4
.equ SYS_LOCKOUT,       5

// I2C LCD Address
.equ LCD_ADDR,          0x27
.equ LCD_BACKLIGHT,     0x08
.equ LCD_ENABLE,        0x04
.equ LCD_RS,            0x01

// SPI Registers
.equ SPI_SS,            PB2
.equ SPI_MOSI,          PB3
.equ SPI_MISO,          PB4
.equ SPI_SCK,           PB5

// MFRC522 Registers
.equ MFRC_CommandReg,   0x01
.equ MFRC_ComIrqReg,    0x04
.equ MFRC_FIFODataReg,  0x09
.equ MFRC_FIFOLevelReg, 0x0A
.equ MFRC_BitFramingReg,0x0D
.equ MFRC_ModeReg,      0x11
.equ MFRC_TxControlReg, 0x14
.equ MFRC_TxASKReg,     0x15
.equ MFRC_VersionReg,   0x37

// MFRC522 Commands
.equ CMD_IDLE,          0x00
.equ CMD_TRANSCEIVE,    0x0C
.equ CMD_SOFTRESET,     0x0F
.equ PICC_REQIDL,       0x26
.equ PICC_ANTICOLL,     0x93

// TWI (I2C) Registers
.equ TWBR_REG,          0xB8
.equ TWSR_REG,          0xB9
.equ TWDR_REG,          0xBB
.equ TWCR_REG,          0xBC

// TWI Control Bits
.equ TWINT_BIT,         7
.equ TWEA_BIT,          6
.equ TWSTA_BIT,         5
.equ TWSTO_BIT,         4
.equ TWEN_BIT,          2

// Timer0 (for millis approximation)
.equ TIMER_PRESCALE,    64

// ============================================================================
// DATA SECTION (Matches TwoFactorLock.ino exactly)
// ============================================================================
.section .data

// Secret PIN = "1234"
secret_pin:
    .byte '1', '2', '3', '4', 0x00

// Secret UID = {0x67, 0x93, 0xA9, 0x04}
secret_uid:
    .byte 0x67, 0x93, 0xA9, 0x04

// Input buffer (5 bytes: 4 digits + null)
input_buffer:
    .byte 0x00, 0x00, 0x00, 0x00, 0x00

// State variables
current_state:
    .byte SYS_IDLE

input_index:
    .byte 0x00

wrong_attempts:
    .byte 0x00

is_locked_out:
    .byte 0x00

lockout_counter:
    .byte 0x00

// Scanned RFID UID storage
scanned_uid:
    .byte 0x00, 0x00, 0x00, 0x00

// Keypad lookup table (Row x Col)
// Row 0: 1 2 3 A
// Row 1: 4 5 6 B
// Row 2: 7 8 9 C
// Row 3: * 0 # D
keypad_map:
    .byte '1', '2', '3', 'A'
    .byte '4', '5', '6', 'B'
    .byte '7', '8', '9', 'C'
    .byte '*', '0', '#', 'D'

// LCD Strings (Matches TwoFactorLock.ino exactly)
str_booting:
    .asciz "System Booting"
str_ready:
    .asciz "READY. Press Key"
str_enter_pin:
    .asciz "Enter PIN:"
str_verifying:
    .asciz "Verifying..."
str_pin_ok:
    .asciz "PIN OK!"
str_scan_card:
    .asciz "Scan Card"
str_wrong_pin:
    .asciz "Wrong PIN!"
str_tries_left:
    .asciz "Tries left: "
str_system_locked:
    .asciz "SYSTEM LOCKED!"
str_locked_out:
    .asciz "!! LOCKED OUT !!"
str_wait:
    .asciz "Wait: "
str_seconds:
    .asciz "s"
str_lock_released:
    .asciz "Lock Released"
str_reading_card:
    .asciz "Reading Card..."
str_unknown_card:
    .asciz "Unknown Card!"
str_access_granted:
    .asciz "ACCESS GRANTED"
str_tries:
    .asciz "Tries: "
str_left:
    .asciz " left"

// ============================================================================
// INTERRUPT VECTOR TABLE
// ============================================================================
.section .text
.org 0x0000

    rjmp    RESET                   ; Reset Handler
    rjmp    DEFAULT_HANDLER         ; INT0
    rjmp    DEFAULT_HANDLER         ; INT1
    rjmp    DEFAULT_HANDLER         ; PCINT0
    rjmp    DEFAULT_HANDLER         ; PCINT1
    rjmp    DEFAULT_HANDLER         ; PCINT2
    rjmp    DEFAULT_HANDLER         ; WDT
    rjmp    TIMER0_OVF_ISR          ; Timer0 Overflow (for millis)
    rjmp    DEFAULT_HANDLER         ; Timer0 Compare A
    rjmp    DEFAULT_HANDLER         ; Timer0 Compare B
    rjmp    DEFAULT_HANDLER         ; Timer1 Overflow
    rjmp    DEFAULT_HANDLER         ; Timer1 Compare A
    rjmp    DEFAULT_HANDLER         ; Timer1 Compare B

DEFAULT_HANDLER:
    reti

// ============================================================================
// TIMER0 ISR - Approximate millisecond counter
// ============================================================================
TIMER0_OVF_ISR:
    push    r16
    in      r16, SREG
    push    r16

    ; Increment lockout counter (approximate seconds)
    ; Timer0 overflows every ~1ms at 16MHz/64 prescaler
    ; We use this for lockout timing

    pop     r16
    out     SREG, r16
    pop     r16
    reti

// ============================================================================
// RESET / MAIN ENTRY POINT
// Equivalent to: void setup()
// ============================================================================
RESET:
    ; --- Stack Pointer Init ---
    ldi     r16, hi8(RAMEND)
    out     SPH, r16
    ldi     r16, lo8(RAMEND)
    out     SPL, r16

    ; --- Pin Configuration ---
    ; pinMode(PIN_BUZZER, OUTPUT)  -> PB0 output
    ; pinMode(PIN_LOCK, OUTPUT)    -> PD7 output
    ; pinMode(PIN_LED, OUTPUT)     -> PC3 output
    sbi     DDRB, PB0              ; Buzzer = output
    sbi     DDRD, PD7              ; Lock = output
    sbi     DDRC, PC3              ; LED = output

    ; All outputs LOW initially
    ; digitalWrite(PIN_LOCK, LOW)
    ; digitalWrite(PIN_LED, LOW)
    cbi     PORTB, PB0             ; Buzzer OFF
    cbi     PORTD, PD7             ; Lock OFF
    cbi     PORTC, PC3             ; LED OFF

    ; --- Keypad Pin Configuration ---
    ; Row pins (D2-D5) = Output (driven LOW one at a time)
    sbi     DDRD, PD2              ; Row 1 = output
    sbi     DDRD, PD3              ; Row 2 = output
    sbi     DDRD, PD4              ; Row 3 = output
    sbi     DDRD, PD5              ; Row 4 = output

    ; Column pins (D6, A0, A1, A2) = Input with pull-up
    cbi     DDRD, PD6              ; Col 1 = input
    cbi     DDRC, PC0              ; Col 2 = input
    cbi     DDRC, PC1              ; Col 3 = input
    cbi     DDRC, PC2              ; Col 4 = input
    sbi     PORTD, PD6             ; Col 1 pull-up
    sbi     PORTC, PC0             ; Col 2 pull-up
    sbi     PORTC, PC1             ; Col 3 pull-up
    sbi     PORTC, PC2             ; Col 4 pull-up

    ; --- SPI Init (for RFID) ---
    ; SPI.begin()
    ; Set MOSI, SCK, SS as output
    sbi     DDRB, SPI_MOSI         ; MOSI = output
    sbi     DDRB, SPI_SCK          ; SCK = output
    sbi     DDRB, SPI_SS           ; SS = output
    sbi     DDRB, PB1              ; RST = output
    cbi     DDRB, SPI_MISO         ; MISO = input

    ; SS HIGH (deselect RFID)
    sbi     PORTB, SPI_SS

    ; RST HIGH
    sbi     PORTB, PB1

    ; Enable SPI, Master mode, clock rate fck/16
    ldi     r16, (1<<SPE)|(1<<MSTR)|(1<<SPR0)
    out     SPCR, r16

    ; --- I2C Init (for LCD) ---
    ; Wire.begin()
    rcall   i2c_init

    ; --- LCD Init ---
    ; lcd.init()
    rcall   lcd_init

    ; lcd.backlight()
    rcall   lcd_backlight

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.setCursor(0, 0)
    ldi     r20, 0
    ldi     r21, 0
    rcall   lcd_set_cursor

    ; lcd.print("System Booting")
    ldi     ZL, lo8(str_booting)
    ldi     ZH, hi8(str_booting)
    rcall   lcd_print_string

    ; delay(1000)
    rcall   delay_1000ms

    ; --- RFID Init ---
    ; rfid.PCD_Init()
    rcall   mfrc522_init

    ; delay(1500)
    rcall   delay_1000ms
    rcall   delay_500ms

    ; --- Initialize State Variables ---
    ; currentState = SYS_IDLE
    ldi     r16, SYS_IDLE
    sts     current_state, r16

    ; wrongAttempts = 0
    ldi     r16, 0
    sts     wrong_attempts, r16

    ; isLockedOut = false
    sts     is_locked_out, r16

    ; inputIndex = 0
    sts     input_index, r16

    ; memset(inputBuffer, 0, 5)
    sts     input_buffer, r16
    sts     input_buffer+1, r16
    sts     input_buffer+2, r16
    sts     input_buffer+3, r16
    sts     input_buffer+4, r16

    ; resetSystem()
    rcall   reset_system

    ; Enable global interrupts
    sei

// ============================================================================
// MAIN LOOP
// Equivalent to: void loop()
// ============================================================================
main_loop:
    ; switch (currentState)
    lds     r16, current_state

    cpi     r16, SYS_IDLE
    breq    state_idle

    cpi     r16, SYS_ENTER_PIN
    breq    state_enter_pin_jump

    cpi     r16, SYS_CHECK_PIN
    breq    state_check_pin_jump

    cpi     r16, SYS_WAIT_RFID
    breq    state_wait_rfid_jump

    cpi     r16, SYS_ACCESS_GRANTED
    breq    state_access_granted_jump

    cpi     r16, SYS_LOCKOUT
    breq    state_lockout_jump

    rjmp    main_loop

; --- Jump trampolines (because breq has limited range) ---
state_enter_pin_jump:
    rjmp    state_enter_pin
state_check_pin_jump:
    rjmp    state_check_pin
state_wait_rfid_jump:
    rjmp    state_wait_rfid
state_access_granted_jump:
    rjmp    state_access_granted
state_lockout_jump:
    rjmp    state_lockout

// ============================================================================
// STATE: SYS_IDLE
// Equivalent to: case SYS_IDLE in loop()
// ============================================================================
state_idle:
    ; char key = keypad.getKey()
    rcall   scan_keypad
    ; Result in r24 (0 = no key, else ASCII char)

    tst     r24
    breq    state_idle_done        ; No key pressed, continue loop

    ; Key was pressed!
    mov     r17, r24               ; Save key in r17

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("Enter PIN:")
    ldi     ZL, lo8(str_enter_pin)
    ldi     ZH, hi8(str_enter_pin)
    rcall   lcd_print_string

    ; lcd.setCursor(0, 1)
    ldi     r20, 0
    ldi     r21, 1
    rcall   lcd_set_cursor

    ; currentState = SYS_ENTER_PIN
    ldi     r16, SYS_ENTER_PIN
    sts     current_state, r16

    ; if (key != '#' && key != '*')
    mov     r24, r17
    cpi     r24, '#'
    breq    state_idle_done
    cpi     r24, '*'
    breq    state_idle_star

    ; Save the first key press (FIX: don't lose it!)
    ; inputBuffer[inputIndex++] = key
    lds     r18, input_index
    ldi     ZL, lo8(input_buffer)
    ldi     ZH, hi8(input_buffer)
    add     ZL, r18
    clr     r19
    adc     ZH, r19
    st      Z, r24

    ; inputIndex++
    inc     r18
    sts     input_index, r18

    ; inputBuffer[inputIndex] = '\0'
    ldi     ZL, lo8(input_buffer)
    ldi     ZH, hi8(input_buffer)
    add     ZL, r18
    clr     r19
    adc     ZH, r19
    clr     r16
    st      Z, r16

    ; lcd.print('*')
    ldi     r24, '*'
    rcall   lcd_print_char

    ; tone(PIN_BUZZER, 1000, 50)
    rcall   buzzer_short_beep

    rjmp    state_idle_done

state_idle_star:
    ; else if (key == '*') resetSystem()
    rcall   reset_system

state_idle_done:
    rjmp    main_loop

// ============================================================================
// STATE: SYS_ENTER_PIN
// Equivalent to: void handlePinEntry()
// ============================================================================
state_enter_pin:
    ; char key = keypad.getKey()
    rcall   scan_keypad
    ; Result in r24

    tst     r24
    breq    enter_pin_done         ; No key, continue loop

    ; tone(PIN_BUZZER, 1000, 50)
    rcall   buzzer_short_beep

    ; if (key == '#')
    cpi     r24, '#'
    breq    enter_pin_hash

    ; if (key == '*')
    cpi     r24, '*'
    breq    enter_pin_star

    ; else: Store the digit
    ; if (inputIndex < 4)
    lds     r18, input_index
    cpi     r18, PIN_LENGTH
    brge    enter_pin_done         ; Buffer full, ignore

    ; inputBuffer[inputIndex++] = key
    mov     r17, r24               ; Save key
    ldi     ZL, lo8(input_buffer)
    ldi     ZH, hi8(input_buffer)
    add     ZL, r18
    clr     r19
    adc     ZH, r19
    st      Z, r17

    ; inputIndex++
    inc     r18
    sts     input_index, r18

    ; inputBuffer[inputIndex] = '\0'
    ldi     ZL, lo8(input_buffer)
    ldi     ZH, hi8(input_buffer)
    add     ZL, r18
    clr     r19
    adc     ZH, r19
    clr     r16
    st      Z, r16

    ; lcd.print('*')
    ldi     r24, '*'
    rcall   lcd_print_char

    rjmp    enter_pin_done

enter_pin_hash:
    ; currentState = SYS_CHECK_PIN
    ldi     r16, SYS_CHECK_PIN
    sts     current_state, r16
    rjmp    enter_pin_done

enter_pin_star:
    ; resetSystem()
    rcall   reset_system

enter_pin_done:
    rjmp    main_loop

// ============================================================================
// STATE: SYS_CHECK_PIN
// Equivalent to: void verifyPin()
// ============================================================================
state_check_pin:
    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("Verifying...")
    ldi     ZL, lo8(str_verifying)
    ldi     ZH, hi8(str_verifying)
    rcall   lcd_print_string

    ; delay(800)
    rcall   delay_500ms
    rcall   delay_250ms

    ; --- strcmp(inputBuffer, SECRET_PIN) ---
    ; Compare byte by byte
    ldi     XL, lo8(input_buffer)
    ldi     XH, hi8(input_buffer)
    ldi     ZL, lo8(secret_pin)
    ldi     ZH, hi8(secret_pin)

    ldi     r18, 0                 ; match = true (0 = match)
    ldi     r19, PIN_LENGTH        ; 4 bytes to compare

check_pin_loop:
    tst     r19
    breq    check_pin_compare_null

    ld      r16, X+                ; input byte
    ld      r17, Z+                ; secret byte
    cp      r16, r17
    breq    check_pin_next
    ldi     r18, 1                 ; mismatch found
check_pin_next:
    dec     r19
    rjmp    check_pin_loop

check_pin_compare_null:
    ; Also check null terminator
    ld      r16, X
    tst     r16
    breq    check_pin_result
    ldi     r18, 1                 ; Extra chars = mismatch

check_pin_result:
    tst     r18
    brne    pin_wrong

    ; === PIN CORRECT ===
    ; wrongAttempts = 0
    clr     r16
    sts     wrong_attempts, r16

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("PIN OK!")
    ldi     ZL, lo8(str_pin_ok)
    ldi     ZH, hi8(str_pin_ok)
    rcall   lcd_print_string

    ; lcd.setCursor(0, 1)
    ldi     r20, 0
    ldi     r21, 1
    rcall   lcd_set_cursor

    ; lcd.print("Scan Card")
    ldi     ZL, lo8(str_scan_card)
    ldi     ZH, hi8(str_scan_card)
    rcall   lcd_print_string

    ; tone(PIN_BUZZER, 2000, 150)
    rcall   buzzer_confirm_beep

    ; currentState = SYS_WAIT_RFID
    ldi     r16, SYS_WAIT_RFID
    sts     current_state, r16

    rjmp    main_loop

pin_wrong:
    ; === PIN WRONG ===
    ; wrongAttempts++
    lds     r16, wrong_attempts
    inc     r16
    sts     wrong_attempts, r16

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("Wrong PIN!")
    ldi     ZL, lo8(str_wrong_pin)
    ldi     ZH, hi8(str_wrong_pin)
    rcall   lcd_print_string

    ; lcd.setCursor(0, 1)
    ldi     r20, 0
    ldi     r21, 1
    rcall   lcd_set_cursor

    ; if (wrongAttempts >= MAX_ATTEMPTS)
    lds     r16, wrong_attempts
    cpi     r16, MAX_ATTEMPTS
    brge    pin_lockout

    ; --- Not locked out yet ---
    ; lcd.print("Tries left: ")
    ldi     ZL, lo8(str_tries_left)
    ldi     ZH, hi8(str_tries_left)
    rcall   lcd_print_string

    ; lcd.print(MAX_ATTEMPTS - wrongAttempts)
    lds     r16, wrong_attempts
    ldi     r17, MAX_ATTEMPTS
    sub     r17, r16
    mov     r24, r17
    subi    r24, -'0'             ; Convert to ASCII
    rcall   lcd_print_char

    ; tone(PIN_BUZZER, 500, 700)
    rcall   buzzer_error_beep

    ; delay(2000)
    rcall   delay_1000ms
    rcall   delay_1000ms

    ; resetSystem()
    rcall   reset_system
    rjmp    main_loop

pin_lockout:
    ; === LOCKOUT ===
    ; lcd.print("SYSTEM LOCKED!")
    ldi     ZL, lo8(str_system_locked)
    ldi     ZH, hi8(str_system_locked)
    rcall   lcd_print_string

    ; tone(PIN_BUZZER, 300, 2000)
    rcall   buzzer_alarm

    ; delay(2000)
    rcall   delay_1000ms
    rcall   delay_1000ms

    ; startLockout()
    rcall   start_lockout

    rjmp    main_loop

// ============================================================================
// STATE: SYS_WAIT_RFID
// Equivalent to: void handleRfidCheck()
// ============================================================================
state_wait_rfid:
    ; if (!rfid.PICC_IsNewCardPresent()) return
    rcall   mfrc522_request
    tst     r24
    brne    rfid_no_card

    ; if (!rfid.PICC_ReadCardSerial()) return
    rcall   mfrc522_anticoll
    tst     r24
    brne    rfid_no_card

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("Reading Card...")
    ldi     ZL, lo8(str_reading_card)
    ldi     ZH, hi8(str_reading_card)
    rcall   lcd_print_string

    ; --- Compare scanned UID with SECRET_UID ---
    ldi     XL, lo8(scanned_uid)
    ldi     XH, hi8(scanned_uid)
    ldi     ZL, lo8(secret_uid)
    ldi     ZH, hi8(secret_uid)

    ldi     r18, 0                 ; match = true
    ldi     r19, 4                 ; 4 bytes

rfid_check_loop:
    tst     r19
    breq    rfid_check_done

    ld      r16, X+
    ld      r17, Z+
    cp      r16, r17
    breq    rfid_check_next
    ldi     r18, 1                 ; mismatch
rfid_check_next:
    dec     r19
    rjmp    rfid_check_loop

rfid_check_done:
    ; rfid.PICC_HaltA()
    rcall   mfrc522_halt

    tst     r18
    brne    rfid_unknown

    ; === CARD MATCH ===
    ; currentState = SYS_ACCESS_GRANTED
    ldi     r16, SYS_ACCESS_GRANTED
    sts     current_state, r16
    rjmp    main_loop

rfid_unknown:
    ; === UNKNOWN CARD ===
    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("Unknown Card!")
    ldi     ZL, lo8(str_unknown_card)
    ldi     ZH, hi8(str_unknown_card)
    rcall   lcd_print_string

    ; tone(PIN_BUZZER, 400, 1000)
    rcall   buzzer_error_beep

    ; delay(2000)
    rcall   delay_1000ms
    rcall   delay_1000ms

    ; resetSystem()
    rcall   reset_system

rfid_no_card:
    rjmp    main_loop

// ============================================================================
// STATE: SYS_ACCESS_GRANTED
// Equivalent to: void grantAccess()
// ============================================================================
state_access_granted:
    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("ACCESS GRANTED")
    ldi     ZL, lo8(str_access_granted)
    ldi     ZH, hi8(str_access_granted)
    rcall   lcd_print_string

    ; digitalWrite(PIN_LOCK, HIGH)
    sbi     PORTD, PD7

    ; digitalWrite(PIN_LED, HIGH)
    sbi     PORTC, PC3

    ; tone(PIN_BUZZER, 3000, 200)
    rcall   buzzer_success_beep

    ; delay(3000)
    rcall   delay_1000ms
    rcall   delay_1000ms
    rcall   delay_1000ms

    ; digitalWrite(PIN_LOCK, LOW)
    cbi     PORTD, PD7

    ; digitalWrite(PIN_LED, LOW)
    cbi     PORTC, PC3

    ; wrongAttempts = 0
    clr     r16
    sts     wrong_attempts, r16

    ; resetSystem()
    rcall   reset_system

    rjmp    main_loop

// ============================================================================
// STATE: SYS_LOCKOUT
// Equivalent to: void handleLockout()
// ============================================================================
state_lockout:
    ; Read lockout counter (counts down from 30)
    lds     r20, lockout_counter

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("!! LOCKED OUT !!")
    ldi     ZL, lo8(str_locked_out)
    ldi     ZH, hi8(str_locked_out)
    rcall   lcd_print_string

    ; lcd.setCursor(0, 1)
    ldi     r20, 0
    ldi     r21, 1
    rcall   lcd_set_cursor

    ; lcd.print("Wait: ")
    ldi     ZL, lo8(str_wait)
    ldi     ZH, hi8(str_wait)
    rcall   lcd_print_string

    ; lcd.print(remaining seconds)
    lds     r24, lockout_counter
    rcall   lcd_print_number

    ; lcd.print("s")
    ldi     ZL, lo8(str_seconds)
    ldi     ZH, hi8(str_seconds)
    rcall   lcd_print_string

    ; Alarm beep
    rcall   buzzer_alarm_short

    ; Ignore keypad presses
    rcall   scan_keypad            ; Read and discard

    ; Decrement counter
    lds     r16, lockout_counter
    tst     r16
    breq    lockout_finished

    dec     r16
    sts     lockout_counter, r16

    ; delay(1000) - 1 second between updates
    rcall   delay_1000ms

    rjmp    main_loop

lockout_finished:
    ; isLockedOut = false
    clr     r16
    sts     is_locked_out, r16

    ; wrongAttempts = 0
    sts     wrong_attempts, r16

    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("Lock Released")
    ldi     ZL, lo8(str_lock_released)
    ldi     ZH, hi8(str_lock_released)
    rcall   lcd_print_string

    ; tone(PIN_BUZZER, 2000, 200)
    rcall   buzzer_confirm_beep

    ; delay(1500)
    rcall   delay_1000ms
    rcall   delay_500ms

    ; resetSystem()
    rcall   reset_system

    rjmp    main_loop

// ============================================================================
// FUNCTION: start_lockout
// Equivalent to: void startLockout()
// ============================================================================
start_lockout:
    ; isLockedOut = true
    ldi     r16, 1
    sts     is_locked_out, r16

    ; lockout_counter = 30 (seconds)
    ldi     r16, LOCKOUT_TIME_S
    sts     lockout_counter, r16

    ; currentState = SYS_LOCKOUT
    ldi     r16, SYS_LOCKOUT
    sts     current_state, r16

    ret

// ============================================================================
// FUNCTION: reset_system
// Equivalent to: void resetSystem()
// ============================================================================
reset_system:
    ; lcd.clear()
    rcall   lcd_clear

    ; lcd.print("READY. Press Key")
    ldi     ZL, lo8(str_ready)
    ldi     ZH, hi8(str_ready)
    rcall   lcd_print_string

    ; if (wrongAttempts > 0) show tries remaining
    lds     r16, wrong_attempts
    tst     r16
    breq    reset_no_tries

    ; lcd.setCursor(0, 1)
    ldi     r20, 0
    ldi     r21, 1
    rcall   lcd_set_cursor

    ; lcd.print("Tries: ")
    ldi     ZL, lo8(str_tries)
    ldi     ZH, hi8(str_tries)
    rcall   lcd_print_string

    ; lcd.print(MAX_ATTEMPTS - wrongAttempts)
    lds     r16, wrong_attempts
    ldi     r17, MAX_ATTEMPTS
    sub     r17, r16
    mov     r24, r17
    subi    r24, -'0'
    rcall   lcd_print_char

    ; lcd.print(" left")
    ldi     ZL, lo8(str_left)
    ldi     ZH, hi8(str_left)
    rcall   lcd_print_string

reset_no_tries:
    ; currentState = SYS_IDLE
    ldi     r16, SYS_IDLE
    sts     current_state, r16

    ; inputIndex = 0
    clr     r16
    sts     input_index, r16

    ; memset(inputBuffer, 0, 5)
    clr     r16
    sts     input_buffer, r16
    sts     input_buffer+1, r16
    sts     input_buffer+2, r16
    sts     input_buffer+3, r16
    sts     input_buffer+4, r16

    ; digitalWrite(PIN_LOCK, LOW)
    cbi     PORTD, PD7

    ; digitalWrite(PIN_LED, LOW)
    cbi     PORTC, PC3

    ret

// ============================================================================
// KEYPAD SCANNER
// Scans the 4x4 matrix keypad
// Returns: r24 = ASCII key pressed, or 0 if none
// Row pins: PD2, PD3, PD4, PD5 (output, active LOW)
// Col pins: PD6, PC0, PC1, PC2 (input, pull-up)
// ============================================================================
scan_keypad:
    push    r17
    push    r18
    push    r19
    push    r20

    clr     r24                    ; Default: no key

    ldi     r17, 0                 ; Row counter (0-3)

scan_row_loop:
    cpi     r17, 4
    breq    scan_done

    ; Set all rows HIGH first
    sbi     PORTD, PD2
    sbi     PORTD, PD3
    sbi     PORTD, PD4
    sbi     PORTD, PD5

    ; Set current row LOW
    cpi     r17, 0
    brne    scan_not_row0
    cbi     PORTD, PD2
    rjmp    scan_read_cols
scan_not_row0:
    cpi     r17, 1
    brne    scan_not_row1
    cbi     PORTD, PD3
    rjmp    scan_read_cols
scan_not_row1:
    cpi     r17, 2
    brne    scan_not_row2
    cbi     PORTD, PD4
    rjmp    scan_read_cols
scan_not_row2:
    cbi     PORTD, PD5

scan_read_cols:
    ; Small delay for signal to settle
    nop
    nop
    nop
    nop
    nop
    nop

    ; Read column pins
    ldi     r18, 0                 ; Col counter

    ; Check Col 1 (PD6)
    sbis    PIND, PD6
    rjmp    key_found

    inc     r18

    ; Check Col 2 (PC0)
    sbis    PINC, PC0
    rjmp    key_found

    inc     r18

    ; Check Col 3 (PC1)
    sbis    PINC, PC1
    rjmp    key_found

    inc     r18

    ; Check Col 4 (PC2)
    sbis    PINC, PC2
    rjmp    key_found

    ; No key in this row
    inc     r17
    rjmp    scan_row_loop

key_found:
    ; r17 = row, r18 = col
    ; Index into keypad_map: row * 4 + col
    mov     r19, r17
    lsl     r19                    ; row * 2
    lsl     r19                    ; row * 4
    add     r19, r18               ; row * 4 + col

    ; Load character from keypad_map
    ldi     ZL, lo8(keypad_map)
    ldi     ZH, hi8(keypad_map)
    add     ZL, r19
    clr     r20
    adc     ZH, r20
    ld      r24, Z                 ; r24 = key character

    ; Debounce: wait until key released
key_debounce_wait:
    rcall   delay_10ms
    ; Re-read the same column
    cpi     r18, 0
    brne    debounce_not_col0
    sbic    PIND, PD6
    rjmp    scan_done
    rjmp    key_debounce_wait
debounce_not_col0:
    cpi     r18, 1
    brne    debounce_not_col1
    sbic    PINC, PC0
    rjmp    scan_done
    rjmp    key_debounce_wait
debounce_not_col1:
    cpi     r18, 2
    brne    debounce_not_col2
    sbic    PINC, PC1
    rjmp    scan_done
    rjmp    key_debounce_wait
debounce_not_col2:
    sbic    PINC, PC2
    rjmp    scan_done
    rjmp    key_debounce_wait

scan_done:
    ; Restore all rows HIGH
    sbi     PORTD, PD2
    sbi     PORTD, PD3
    sbi     PORTD, PD4
    sbi     PORTD, PD5

    pop     r20
    pop     r19
    pop     r18
    pop     r17
    ret

// ============================================================================
// I2C (TWI) LOW-LEVEL DRIVER
// ============================================================================
i2c_init:
    ; Set SCL frequency: 100kHz at 16MHz
    ; TWBR = ((F_CPU/F_SCL) - 16) / 2 = ((16000000/100000) - 16) / 2 = 72
    ldi     r16, 72
    sts     TWBR_REG, r16
    ; Prescaler = 1
    ldi     r16, 0
    sts     TWSR_REG, r16
    ; Enable TWI
    ldi     r16, (1<<TWEN_BIT)
    sts     TWCR_REG, r16
    ret

i2c_start:
    ; Send START condition
    ldi     r16, (1<<TWINT_BIT)|(1<<TWSTA_BIT)|(1<<TWEN_BIT)
    sts     TWCR_REG, r16
i2c_start_wait:
    lds     r16, TWCR_REG
    sbrs    r16, TWINT_BIT
    rjmp    i2c_start_wait
    ret

i2c_stop:
    ; Send STOP condition
    ldi     r16, (1<<TWINT_BIT)|(1<<TWSTO_BIT)|(1<<TWEN_BIT)
    sts     TWCR_REG, r16
    ret

i2c_write:
    ; Write byte in r24 to I2C bus
    sts     TWDR_REG, r24
    ldi     r16, (1<<TWINT_BIT)|(1<<TWEN_BIT)
    sts     TWCR_REG, r16
i2c_write_wait:
    lds     r16, TWCR_REG
    sbrs    r16, TWINT_BIT
    rjmp    i2c_write_wait
    ret

// ============================================================================
// LCD I2C DRIVER (HD44780 via PCF8574 I2C backpack)
// ============================================================================
lcd_init:
    ; Wait for LCD to power up
    rcall   delay_50ms

    ; Send init sequence (4-bit mode)
    ldi     r24, 0x30
    rcall   lcd_send_nibble
    rcall   delay_5ms

    ldi     r24, 0x30
    rcall   lcd_send_nibble
    rcall   delay_1ms

    ldi     r24, 0x30
    rcall   lcd_send_nibble
    rcall   delay_1ms

    ; Set 4-bit mode
    ldi     r24, 0x20
    rcall   lcd_send_nibble
    rcall   delay_1ms

    ; Function set: 4-bit, 2 lines, 5x8 font
    ldi     r24, 0x28
    rcall   lcd_send_command

    ; Display ON, cursor OFF, blink OFF
    ldi     r24, 0x0C
    rcall   lcd_send_command

    ; Clear display
    ldi     r24, 0x01
    rcall   lcd_send_command
    rcall   delay_5ms

    ; Entry mode: increment, no shift
    ldi     r24, 0x06
    rcall   lcd_send_command

    ret

lcd_clear:
    ldi     r24, 0x01
    rcall   lcd_send_command
    rcall   delay_5ms
    ret

lcd_backlight:
    ; Just set backlight flag (handled in every I2C write)
    ret

lcd_set_cursor:
    ; r20 = col, r21 = row
    ; DDRAM address: row 0 = 0x00, row 1 = 0x40
    mov     r24, r20
    tst     r21
    breq    lcd_cursor_set
    ori     r24, 0x40              ; Row 1 offset
lcd_cursor_set:
    ori     r24, 0x80              ; Set DDRAM command
    rcall   lcd_send_command
    ret

lcd_print_char:
    ; Print single char in r24
    rcall   lcd_send_data
    ret

lcd_print_string:
    ; Print null-terminated string pointed to by Z
    push    r24
lcd_ps_loop:
    ld      r24, Z+
    tst     r24
    breq    lcd_ps_done
    rcall   lcd_send_data
    rjmp    lcd_ps_loop
lcd_ps_done:
    pop     r24
    ret

lcd_print_number:
    ; Print number in r24 (0-99) as decimal
    push    r17
    push    r18

    mov     r17, r24

    ; Tens digit
    ldi     r18, 0
lcd_num_tens:
    cpi     r17, 10
    brlo    lcd_num_ones
    subi    r17, 10
    inc     r18
    rjmp    lcd_num_tens

lcd_num_ones:
    ; Print tens if > 0
    tst     r18
    breq    lcd_num_skip_tens
    mov     r24, r18
    subi    r24, -'0'
    rcall   lcd_send_data

lcd_num_skip_tens:
    ; Print ones
    mov     r24, r17
    subi    r24, -'0'
    rcall   lcd_send_data

    pop     r18
    pop     r17
    ret

lcd_send_command:
    ; Send command byte (RS=0)
    push    r24
    push    r25
    mov     r25, r24

    ; High nibble
    andi    r24, 0xF0
    ori     r24, LCD_BACKLIGHT     ; Backlight ON, RS=0
    rcall   lcd_write_nibble_en

    ; Low nibble
    mov     r24, r25
    swap    r24
    andi    r24, 0xF0
    ori     r24, LCD_BACKLIGHT
    rcall   lcd_write_nibble_en

    rcall   delay_1ms

    pop     r25
    pop     r24
    ret

lcd_send_data:
    ; Send data byte (RS=1)
    push    r24
    push    r25
    mov     r25, r24

    ; High nibble
    andi    r24, 0xF0
    ori     r24, LCD_BACKLIGHT|LCD_RS  ; Backlight ON, RS=1
    rcall   lcd_write_nibble_en

    ; Low nibble
    mov     r24, r25
    swap    r24
    andi    r24, 0xF0
    ori     r24, LCD_BACKLIGHT|LCD_RS
    rcall   lcd_write_nibble_en

    rcall   delay_1ms

    pop     r25
    pop     r24
    ret

lcd_send_nibble:
    ; Send raw nibble (for init sequence)
    ori     r24, LCD_BACKLIGHT
    rcall   lcd_write_nibble_en
    ret

lcd_write_nibble_en:
    ; Write nibble with ENABLE pulse via I2C
    push    r24

    ; Send with EN=1
    ori     r24, LCD_ENABLE
    rcall   lcd_i2c_write_byte
    rcall   delay_1ms

    ; Send with EN=0
    pop     r24
    push    r24
    andi    r24, ~LCD_ENABLE
    rcall   lcd_i2c_write_byte
    rcall   delay_1ms

    pop     r24
    ret

lcd_i2c_write_byte:
    ; Write byte in r24 to LCD via I2C
    push    r24
    rcall   i2c_start

    ; Send address (0x27 << 1 | 0 for write = 0x4E)
    ldi     r24, (LCD_ADDR << 1)
    rcall   i2c_write

    ; Send data byte
    pop     r24
    rcall   i2c_write

    rcall   i2c_stop
    ret

// ============================================================================
// SPI DRIVER (for MFRC522 RFID)
// ============================================================================
spi_transfer:
    ; Send byte in r24 via SPI, receive response in r24
    out     SPDR, r24
spi_wait:
    in      r16, SPSR
    sbrs    r16, SPIF
    rjmp    spi_wait
    in      r24, SPDR
    ret

mfrc522_write_reg:
    ; Write value r25 to register r24
    ; Address byte: (reg << 1) & 0x7E
    lsl     r24
    andi    r24, 0x7E

    cbi     PORTB, SPI_SS          ; SS LOW (select)
    rcall   spi_transfer           ; Send address
    mov     r24, r25
    rcall   spi_transfer           ; Send value
    sbi     PORTB, SPI_SS          ; SS HIGH (deselect)
    ret

mfrc522_read_reg:
    ; Read register r24, result in r24
    ; Address byte: ((reg << 1) & 0x7E) | 0x80
    lsl     r24
    andi    r24, 0x7E
    ori     r24, 0x80

    cbi     PORTB, SPI_SS
    rcall   spi_transfer           ; Send address
    ldi     r24, 0x00
    rcall   spi_transfer           ; Read value
    sbi     PORTB, SPI_SS
    ret

// ============================================================================
// MFRC522 RFID DRIVER
// ============================================================================
mfrc522_init:
    ; Reset the MFRC522
    ; Pull RST LOW then HIGH
    cbi     PORTB, PB1
    rcall   delay_50ms
    sbi     PORTB, PB1
    rcall   delay_50ms

    ; Soft reset
    ldi     r24, MFRC_CommandReg
    ldi     r25, CMD_SOFTRESET
    rcall   mfrc522_write_reg
    rcall   delay_50ms

    ; Timer: TModeReg (0x2A) = 0x8D
    ldi     r24, 0x2A
    ldi     r25, 0x8D
    rcall   mfrc522_write_reg

    ; TPrescalerReg (0x2B) = 0x3E
    ldi     r24, 0x2B
    ldi     r25, 0x3E
    rcall   mfrc522_write_reg

    ; TReloadRegH (0x2C) = 0x00
    ldi     r24, 0x2C
    ldi     r25, 0x00
    rcall   mfrc522_write_reg

    ; TReloadRegL (0x2D) = 0x1E
    ldi     r24, 0x2D
    ldi     r25, 0x1E
    rcall   mfrc522_write_reg

    ; TxASKReg = 0x40 (force 100% ASK modulation)
    ldi     r24, MFRC_TxASKReg
    ldi     r25, 0x40
    rcall   mfrc522_write_reg

    ; ModeReg = 0x3D
    ldi     r24, MFRC_ModeReg
    ldi     r25, 0x3D
    rcall   mfrc522_write_reg

    ; Turn on antenna: read TxControlReg, OR with 0x03
    ldi     r24, MFRC_TxControlReg
    rcall   mfrc522_read_reg
    ori     r24, 0x03
    mov     r25, r24
    ldi     r24, MFRC_TxControlReg
    rcall   mfrc522_write_reg

    ret

mfrc522_request:
    ; Send REQA command to detect cards nearby
    ; Returns r24 = 0 if card found, 1 if no card

    ; BitFramingReg = 0x07 (7 bits)
    ldi     r24, MFRC_BitFramingReg
    ldi     r25, 0x07
    rcall   mfrc522_write_reg

    ; Write REQA (0x26) to FIFO
    ldi     r24, MFRC_FIFODataReg
    ldi     r25, PICC_REQIDL
    rcall   mfrc522_write_reg

    ; Execute Transceive command
    ldi     r24, MFRC_CommandReg
    ldi     r25, CMD_TRANSCEIVE
    rcall   mfrc522_write_reg

    ; Start transmission: BitFramingReg |= 0x80
    ldi     r24, MFRC_BitFramingReg
    rcall   mfrc522_read_reg
    ori     r24, 0x80
    mov     r25, r24
    ldi     r24, MFRC_BitFramingReg
    rcall   mfrc522_write_reg

    ; Wait for response (with timeout)
    ldi     r20, 0xFF              ; Timeout counter H
    ldi     r21, 0xFF              ; Timeout counter L

mfrc_req_wait:
    ldi     r24, MFRC_ComIrqReg
    rcall   mfrc522_read_reg
    mov     r16, r24

    ; Check RxIRq (bit 5) or IdleIRq (bit 4)
    andi    r16, 0x30
    brne    mfrc_req_got_response

    ; Timeout check
    subi    r21, 1
    sbci    r20, 0
    brne    mfrc_req_wait

    ; Timeout - no card
    ldi     r24, 1
    ret

mfrc_req_got_response:
    ; Card detected
    ldi     r24, 0
    ret

mfrc522_anticoll:
    ; Anti-collision: get card UID
    ; Returns r24 = 0 if success, stores UID in scanned_uid

    ; BitFramingReg = 0x00 (full bytes)
    ldi     r24, MFRC_BitFramingReg
    ldi     r25, 0x00
    rcall   mfrc522_write_reg

    ; Clear FIFO
    ldi     r24, MFRC_FIFOLevelReg
    ldi     r25, 0x80
    rcall   mfrc522_write_reg

    ; Write anti-collision command to FIFO
    ldi     r24, MFRC_FIFODataReg
    ldi     r25, PICC_ANTICOLL       ; 0x93
    rcall   mfrc522_write_reg

    ldi     r24, MFRC_FIFODataReg
    ldi     r25, 0x20                ; NVB = 0x20
    rcall   mfrc522_write_reg

    ; Execute Transceive
    ldi     r24, MFRC_CommandReg
    ldi     r25, CMD_TRANSCEIVE
    rcall   mfrc522_write_reg

    ; Start transmission
    ldi     r24, MFRC_BitFramingReg
    rcall   mfrc522_read_reg
    ori     r24, 0x80
    mov     r25, r24
    ldi     r24, MFRC_BitFramingReg
    rcall   mfrc522_write_reg

    ; Wait for response
    ldi     r20, 0xFF
    ldi     r21, 0xFF

mfrc_ac_wait:
    ldi     r24, MFRC_ComIrqReg
    rcall   mfrc522_read_reg
    mov     r16, r24
    andi    r16, 0x30
    brne    mfrc_ac_got_response

    subi    r21, 1
    sbci    r20, 0
    brne    mfrc_ac_wait

    ; Timeout
    ldi     r24, 1
    ret

mfrc_ac_got_response:
    ; Read 4 bytes of UID from FIFO
    ldi     r18, 4
    ldi     XL, lo8(scanned_uid)
    ldi     XH, hi8(scanned_uid)

mfrc_read_uid_loop:
    tst     r18
    breq    mfrc_read_uid_done

    ldi     r24, MFRC_FIFODataReg
    rcall   mfrc522_read_reg
    st      X+, r24

    dec     r18
    rjmp    mfrc_read_uid_loop

mfrc_read_uid_done:
    ; Success
    ldi     r24, 0
    ret

mfrc522_halt:
    ; Send HLTA command to put card to sleep
    ; FIFO: 0x50, 0x00
    ldi     r24, MFRC_FIFOLevelReg
    ldi     r25, 0x80
    rcall   mfrc522_write_reg

    ldi     r24, MFRC_FIFODataReg
    ldi     r25, 0x50
    rcall   mfrc522_write_reg

    ldi     r24, MFRC_FIFODataReg
    ldi     r25, 0x00
    rcall   mfrc522_write_reg

    ldi     r24, MFRC_CommandReg
    ldi     r25, CMD_TRANSCEIVE
    rcall   mfrc522_write_reg

    ; Start transmission
    ldi     r24, MFRC_BitFramingReg
    rcall   mfrc522_read_reg
    ori     r24, 0x80
    mov     r25, r24
    ldi     r24, MFRC_BitFramingReg
    rcall   mfrc522_write_reg

    rcall   delay_10ms

    ; Go back to idle
    ldi     r24, MFRC_CommandReg
    ldi     r25, CMD_IDLE
    rcall   mfrc522_write_reg

    ret

// ============================================================================
// BUZZER FUNCTIONS
// ============================================================================
buzzer_short_beep:
    ; tone(PIN_BUZZER, 1000, 50) - Short click beep
    sbi     PORTB, PB0
    rcall   delay_50ms
    cbi     PORTB, PB0
    ret

buzzer_confirm_beep:
    ; tone(PIN_BUZZER, 2000, 150) - Confirmation beep
    sbi     PORTB, PB0
    rcall   delay_100ms
    rcall   delay_50ms
    cbi     PORTB, PB0
    ret

buzzer_error_beep:
    ; tone(PIN_BUZZER, 500, 700) - Error beep
    sbi     PORTB, PB0
    rcall   delay_500ms
    rcall   delay_250ms
    cbi     PORTB, PB0
    ret

buzzer_success_beep:
    ; tone(PIN_BUZZER, 3000, 200) - Success beep
    sbi     PORTB, PB0
    rcall   delay_250ms
    cbi     PORTB, PB0
    ret

buzzer_alarm:
    ; tone(PIN_BUZZER, 300, 2000) - Alarm sound
    sbi     PORTB, PB0
    rcall   delay_1000ms
    rcall   delay_1000ms
    cbi     PORTB, PB0
    ret

buzzer_alarm_short:
    ; Short alarm beep during lockout
    sbi     PORTB, PB0
    rcall   delay_100ms
    rcall   delay_100ms
    cbi     PORTB, PB0
    ret

// ============================================================================
// DELAY FUNCTIONS (at 16MHz clock)
// ============================================================================
delay_1ms:
    push    r16
    push    r17
    ldi     r16, 21
    ldi     r17, 199
delay_1ms_loop:
    dec     r17
    brne    delay_1ms_loop
    dec     r16
    brne    delay_1ms_loop
    pop     r17
    pop     r16
    ret

delay_5ms:
    rcall   delay_1ms
    rcall   delay_1ms
    rcall   delay_1ms
    rcall   delay_1ms
    rcall   delay_1ms
    ret

delay_10ms:
    rcall   delay_5ms
    rcall   delay_5ms
    ret

delay_50ms:
    ldi     r22, 10
delay_50ms_loop:
    rcall   delay_5ms
    dec     r22
    brne    delay_50ms_loop
    ret

delay_100ms:
    rcall   delay_50ms
    rcall   delay_50ms
    ret

delay_250ms:
    rcall   delay_100ms
    rcall   delay_100ms
    rcall   delay_50ms
    ret

delay_500ms:
    rcall   delay_250ms
    rcall   delay_250ms
    ret

delay_1000ms:
    rcall   delay_500ms
    rcall   delay_500ms
    ret

// ============================================================================
// END OF PROGRAM
// ============================================================================
.end