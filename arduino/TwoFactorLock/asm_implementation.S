// TwoFactorLock_ASM_Logic.S
// Pure Assembly implementation of the Two Factor Security Logic
// This logic mirrors the C++ implementation.

// Constants
#define PIN_LENGTH 4

.section .data

// Secrets
secret_pin: .asciz "1234"
secret_uid: .byte 0xDE, 0xAD, 0xBE, 0xEF

// Buffers
input_buffer: .skip 10

.section .text
.global start_security_check
.global check_pin_procedure
.global check_rfid_procedure

// State Machine Simulation in Assembly
start_security_check:
    // This is the theoretical entry point for the security check logic
    // In a full assembly program, this would poll the keypad.
    
    // Simulate: User entered "1234"
    call simulate_input_1234
    
    // Step 1: Check PIN
    ldi r24, lo8(input_buffer)
    ldi r25, hi8(input_buffer)
    call check_pin_procedure
    
    // Check Result (Return in r24: 1=OK, 0=Fail)
    tst r24
    breq handle_failure
    
    // Step 2: If PIN OK, Wait for RFID
    // Simulate reading RFID
    // (In real ASM, this would involve complex SPI register manipulation)
    
    // Call Check RFID (Using secret_uid as input to simulate correct card)
    ldi r24, lo8(secret_uid)
    ldi r25, hi8(secret_uid)
    call check_rfid_procedure
    
    tst r24
    breq handle_failure
    
    // Access Granted
    call trigger_unlock
    ret

handle_failure:
    // Lock kept closed
    ret

// ----------------------------------------------------------------
// Subroutine: Check PIN
// Input: Z pointer to input string
// ----------------------------------------------------------------
check_pin_procedure:
    // pointers already set for hypothetical call
    // Set X to input buffer
    movw r26, r24
    // Set Z to secret
    ldi r30, lo8(secret_pin)
    ldi r31, hi8(secret_pin)
    
pin_loop:
    ld r18, X+  // User Input
    ld r19, Z+  // Secret
    
    cp r18, r19
    brne pin_fail
    
    tst r18     // End of string?
    breq pin_match
    
    rjmp pin_loop

pin_match:
    ldi r24, 1
    ret
pin_fail:
    ldi r24, 0
    ret

// ----------------------------------------------------------------
// Subroutine: Check RFID
// Input: X pointer to 4-byte UID
// ----------------------------------------------------------------
check_rfid_procedure:
    movw r26, r24   // Input UID in X
    
    ldi r30, lo8(secret_uid) // Secret UID in Z
    ldi r31, hi8(secret_uid)
    
    ldi r20, 4      // 4 Bytes
uid_loop:
    ld r18, X+
    ld r19, Z+
    cp r18, r19
    brne rfid_fail
    dec r20
    brne uid_loop
    
    ldi r24, 1      // Match
    ret
rfid_fail:
    ldi r24, 0
    ret

// ----------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------
simulate_input_1234:
    // Fill input buffer with '1','2','3','4',0
    ldi r30, lo8(input_buffer)
    ldi r31, hi8(input_buffer)
    ldi r16, '1'
    st Z+, r16
    ldi r16, '2'
    st Z+, r16
    ldi r16, '3'
    st Z+, r16
    ldi r16, '4'
    st Z+, r16
    ldi r16, 0
    st Z, r16
    ret

trigger_unlock:
    // This assumes PD7 is the lock
    sbi 0x0B, 7 // PORTD |= (1<<7)
    // Delay would happen here
    cbi 0x0B, 7
    ret
