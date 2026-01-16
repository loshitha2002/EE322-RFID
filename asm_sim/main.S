// ATmega328P - Assembly simulation (Stable UART Version)
// Uses Double Speed (U2X) for maximum baud rate accuracy
// UART: 9600 Baud
// F_CPU: 16MHz (Make sure Proteus matches this!)

#ifndef F_CPU
#define F_CPU 16000000UL
#endif

// ----- UART Constants (Double Speed Mode) -----
#define BAUD 9600UL
// Formula for U2X=1 is: F_CPU / (8 * BAUD) - 1
#define UBRR_VAL (((F_CPU + (BAUD*4UL)) / (8UL*BAUD)) - 1UL)

// ----- I/O Registers -----
#define DDRB   0x24
#define PORTB  0x25
#define DDRD   0x2A
#define PORTD  0x2B
#define EICRA  0x69
#define EIMSK  0x3D
#define TCCR1A 0x80
#define TCCR1B 0x81
#define OCR1AL 0x88
#define OCR1AH 0x89
#define TIMSK1 0x6F
#define UCSR0A 0xC0
#define UCSR0B 0xC1
#define UCSR0C 0xC2
#define UBRR0L 0xC4
#define UBRR0H 0xC5
#define UDR0   0xC6
#define EECR   0x3F
#define EEDR   0x40
#define EEARL  0x41
#define EEARH  0x42

// ----- Bit Definitions -----
#define RXC0  7
#define UDRE0 5
#define U2X0  1   // Double speed bit
#define RXEN0 4
#define TXEN0 3
#define UCSZ00 1
#define UCSZ01 2

// SRAM vars
.section .bss
  .global wrong_attempts
wrong_attempts: .skip 1
  .global lockout_sec
lockout_sec:    .skip 1
  .global lock_state
lock_state:     .skip 1
  .global save_req
save_req:       .skip 1
  .global tick_flag
tick_flag:      .skip 1

.section .text
.global main
main:
  // 1. Initialize Stack
  ldi r16, hi8(0x08FF)
  out 0x3E, r16
  ldi r16, lo8(0x08FF)
  out 0x3D, r16

  // 2. Setup IO
  // PD7 (LED) Output
  lds r16, DDRD
  ori r16, (1<<7)
  sts DDRD, r16
  // PB0 (Buzzer) Output
  lds r16, DDRB
  ori r16, (1<<0)
  sts DDRB, r16
  // PD2 (Button) Input + Pullup
  lds r16, DDRD
  andi r16, ~(1<<2)
  sts DDRD, r16
  lds r16, PORTD
  ori r16, (1<<2)
  sts PORTD, r16

  // 3. Setup UART (Double Speed for stability)
  ldi r16, (1<<U2X0)   // Enable Double Speed
  sts UCSR0A, r16
  
  ldi r16, 0
  sts UBRR0H, r16
  ldi r16, lo8(UBRR_VAL)
  sts UBRR0L, r16
  
  ldi r16, (1<<RXEN0)|(1<<TXEN0)
  sts UCSR0B, r16
  ldi r16, (1<<UCSZ01)|(1<<UCSZ00) // 8N1
  sts UCSR0C, r16

  // 4. Setup Timer1 (1s tick)
  ldi r16, 0
  sts TCCR1A, r16
  ldi r16, (1<<3)|(1<<2)|(1<<0) // WGM12(CTC) + CS12+CS10(/1024)
  sts TCCR1B, r16
  // OCR1A = 15624 (approx 1s at 16MHz)
  ldi r16, hi8(15624)
  sts OCR1AH, r16
  ldi r16, lo8(15624)
  sts OCR1AL, r16
  ldi r16, (1<<1) // OCIE1A
  sts TIMSK1, r16

  // 5. Setup INT0 (Falling Edge)
  ldi r16, (1<<1) // ISC01
  sts EICRA, r16
  ldi r16, (1<<0) // INT0
  sts EIMSK, r16

  // 6. Startup Sequence
  ldi r16, 0
  sts wrong_attempts, r16
  sts lockout_sec, r16
  sts save_req, r16
  sts tick_flag, r16
  
  rcall EEPROM_LOAD
  rcall APPLY_LOCK_
  
  // Wait before printing
  rcall DELAY_VISIBLE
  
  // Print '!'
  ldi r16, '!'
  rcall UART_TX
  
  // Print Banner
  rcall PRINT_BANNER
  
  // Blink LED
  rcall STARTUP_BLINK
  
  sei // Enable Interrupts NOW (safe)

MAIN_LOOP:
  // Check heart beat
  lds r16, tick_flag
  tst r16
  breq NO_TICK
  ldi r16, 0
  sts tick_flag, r16
  ldi r16, '.'
  rcall UART_TX
NO_TICK:

  // Check Save
  lds r16, save_req
  tst r16
  breq NO_SAVE
  ldi r16, 0
  sts save_req, r16
  rcall EEPROM_SAVE
  rcall PRINT_SAVED
NO_SAVE:

  // Check UART
  rcall UART_RX_POLL
  brtc MAIN_LOOP
  
  // Echo
  rcall UART_TX
  
  // Logic
  cpi r16, 'A'
  breq DO_AUTH
  cpi r16, 'W'
  breq DO_WRONG
  cpi r16, 'P'
  breq DO_SAVE
  rjmp MAIN_LOOP

// ----- Logic Handlers -----
DO_AUTH:
  lds r17, lockout_sec
  tst r17
  brne MAIN_LOOP
  ldi r16, 1
  sts lock_state, r16
  ldi r16, 0
  sts wrong_attempts, r16
  rcall APPLY_LOCK_
  rcall PRINT_OK
  rcall BEEP_SHORT
  rjmp MAIN_LOOP

DO_WRONG:
  lds r17, lockout_sec
  tst r17
  brne MAIN_LOOP
  lds r16, wrong_attempts
  inc r16
  sts wrong_attempts, r16
  rcall PRINT_WRONG
  rcall BEEP_SHORT
  // Fix: Reload attempts because PRINT_WRONG clobbers r16
  lds r16, wrong_attempts
  cpi r16, 3
  brne MAIN_LOOP
  ldi r16, 30
  sts lockout_sec, r16
  ldi r16, 0
  sts lock_state, r16
  rcall APPLY_LOCK_
  rcall PRINT_LOCKOUT
  rjmp MAIN_LOOP

DO_SAVE:
  rcall EEPROM_SAVE
  rcall PRINT_SAVED
  rcall BEEP_SHORT
  rjmp MAIN_LOOP

// ----- Helpers -----
UART_RX_POLL:
  lds r18, UCSR0A
  sbrs r18, RXC0
  rjmp RX_NONE
  lds r16, UDR0
  set
  ret
RX_NONE:
  clt
  ret

UART_TX:
  // 1. Wait for buffer empty
  lds r18, UCSR0A
  sbrs r18, UDRE0
  rjmp UART_TX
  
  // 2. Write data
  sts UDR0, r16
  
  // 3. Robust Delay for Proteus (approx 10ms)
  // Prevents Virtual Terminal buffer overruns
  push r20
  push r21
  ldi r20, 0
TX_OL: 
  ldi r21, 60
TX_IL:
  dec r21
  brne TX_IL
  dec r20
  brne TX_OL
  pop r21
  pop r20
  
  ret

APPLY_LOCK_:
  lds r16, lock_state
  tst r16
  breq L_OFF
  lds r16, PORTD
  ori r16, (1<<7)
  sts PORTD, r16
  ret
L_OFF:
  lds r16, PORTD
  andi r16, ~(1<<7)
  sts PORTD, r16
  ret

PRINT_Z:
  lpm r16, Z+
  tst r16
  breq P_DONE
  rcall UART_TX
  rjmp PRINT_Z
P_DONE:
  ret

PRINT_BANNER:
  ldi ZH, hi8(msg_banner)
  ldi ZL, lo8(msg_banner)
  rjmp PRINT_Z
PRINT_OK:
  ldi ZH, hi8(msg_ok)
  ldi ZL, lo8(msg_ok)
  rjmp PRINT_Z
PRINT_WRONG:
  ldi ZH, hi8(msg_wrong)
  ldi ZL, lo8(msg_wrong)
  rjmp PRINT_Z
PRINT_LOCKOUT:
  ldi ZH, hi8(msg_lockout)
  ldi ZL, lo8(msg_lockout)
  rjmp PRINT_Z
PRINT_SAVED:
  ldi ZH, hi8(msg_saved)
  ldi ZL, lo8(msg_saved)
  rjmp PRINT_Z

STARTUP_BLINK:
  ldi r22, 3
SB_L:
  lds r16, PORTD
  ori r16, (1<<7)
  sts PORTD, r16
  rcall DELAY_VISIBLE
  lds r16, PORTD
  andi r16, ~(1<<7)
  sts PORTD, r16
  rcall DELAY_VISIBLE
  dec r22
  brne SB_L
  ret

BEEP_SHORT:
  push r16
  push r20
  push r21
  push r19

  // ON
  lds r16, PORTB
  ori r16, 1
  sts PORTB, r16

  // Delay ~50ms
  ldi r19, 10
BEEP_D:
  rcall DELAY_SHORT
  dec r19
  brne BEEP_D

  // OFF
  lds r16, PORTB
  andi r16, 0xFE
  sts PORTB, r16

  pop r19
  pop r21
  pop r20
  pop r16
  ret

DELAY_SHORT:
  ldi r20, 100
DS1: ldi r21, 255
DS2: dec r21
  brne DS2
  dec r20
  brne DS1
  ret

DELAY_VISIBLE:
  ldi r19, 40
DV1: rcall DELAY_SHORT
  dec r19
  brne DV1
  ret

// ----- ISRs -----
.global __vector_1
__vector_1: // INT0
  push r16
  in r16, 0x3F
  push r16
  ldi r16, 1
  sts save_req, r16
  pop r16
  out 0x3F, r16
  pop r16
  reti

.global __vector_11
__vector_11: // Timer1
  push r16
  push r17
  in r16, 0x3F
  push r16
  
  ldi r16, 1
  sts tick_flag, r16

  lds r17, lockout_sec
  tst r17
  breq T_DONE
  dec r17
  sts lockout_sec, r17
  
  // Beep during lockout
  rcall BEEP_SHORT
  
  lds r17, lockout_sec
  tst r17
  brne T_DONE
  // Lockout just ended
  ldi r16, 0
  sts wrong_attempts, r16
  
T_DONE:
  pop r16
  out 0x3F, r16
  pop r17
  pop r16
  reti

// ----- EEPROM Helpers -----
EEPROM_READ_BYTE:
  sbic 0x1F, 1 // Wait EEPE (EECR is 0x1F in IO space or 0x3F in Mem)
  rjmp EEPROM_READ_BYTE
  sts EEARL, r17
  ldi r18, 0
  sts EEARH, r18
  lds r18, EECR
  ori r18, 1
  sts EECR, r18
  lds r16, EEDR
  ret

EEPROM_WRITE_BYTE:
  sbic 0x1F, 1
  rjmp EEPROM_WRITE_BYTE
  sts EEARL, r17
  ldi r18, 0
  sts EEARH, r18
  sts EEDR, r16
  lds r18, EECR
  ori r18, 4 // EEMPE
  sts EECR, r18
  ori r18, 2 // EEPE
  sts EECR, r18
  ret

EEPROM_LOAD:
  ldi r17, 0
  rcall EEPROM_READ_BYTE
  cpi r16, 0xA5
  brne EE_DEF
  ldi r17, 1
  rcall EEPROM_READ_BYTE
  sts lock_state, r16
  ldi r17, 2
  rcall EEPROM_READ_BYTE
  sts wrong_attempts, r16
  // Logic Change: Always reset lockout on boot for simpler testing
  ldi r16, 0
  sts lockout_sec, r16
  ret

EE_DEF:
  ldi r16, 0
  sts lock_state, r16
  sts wrong_attempts, r16
  sts lockout_sec, r16
  ret

EEPROM_SAVE:
  ldi r16, 0xA5
  ldi r17, 0
  rcall EEPROM_WRITE_BYTE
  lds r16, lock_state
  ldi r17, 1
  rcall EEPROM_WRITE_BYTE
  lds r16, wrong_attempts
  ldi r17, 2
  rcall EEPROM_WRITE_BYTE
  lds r16, lockout_sec
  ldi r17, 3
  rcall EEPROM_WRITE_BYTE
  ret

// Strings in .text to ensure LPM finds them correctly
.section .text
.align 2
msg_banner:  .asciz "READY\r\n"
msg_ok:      .asciz "OK\r\n"
msg_wrong:   .asciz "WRONG\r\n"
msg_lockout: .asciz "LOCKOUT 30s\r\n"
msg_saved:   .asciz "SAVED\r\n"
