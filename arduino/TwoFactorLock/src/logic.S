#include <avr/io.h>

// ----- Assembly Logic Module -----
// This file contains the "Secret" Verification Logic
// calling convention: r24, r22... returns in r24

.global asm_check_pincode
.global asm_check_rfid

.section .data
// The Secret Passcode "1234" (null terminated)
secret_pin: .asciz "1234"

// The Secret UID {0xDE, 0xAD, 0xBE, 0xEF}
secret_uid: .byte 0xDE, 0xAD, 0xBE, 0xEF

.section .text

// ------------------------------------------------
// Function: asm_check_pincode
// Arguments: r24 (High byte of string ptr), r25 (Low byte of string ptr)
// Note: In C check_pin(const char* input) -> pointer is passed in r24:r25
// Returns: r24 (1 if match, 0 if fail)
// ------------------------------------------------
asm_check_pincode:
    // Move input pointer to X register (r26:r27)
    movw r26, r24 
    
    // Load address of secret_pin into Z register (r30:r31)
    ldi r30, lo8(secret_pin)
    ldi r31, hi8(secret_pin)

compare_loop:
    ld r18, X+      // Load char from Input (RAM)
    ld r19, Z+      // Load char from Secret (RAM)
    
    cp r18, r19     // Compare
    brne not_match  // If not equal, fail
    
    tst r18         // Check for Null Terminator (0)
    breq match      // If 0, we reached end strings and they were equal
    
    rjmp compare_loop

match:
    ldi r24, 1
    ret

not_match:
    ldi r24, 0
    ret

// ------------------------------------------------
// Function: asm_check_rfid
// Arguments: r24:r25 (Pointer to 4-byte UID array)
// Returns: r24 (1 if match, 0 if fail)
// ------------------------------------------------
asm_check_rfid:
    movw r26, r24   // Input UID in X
    
    ldi r30, lo8(secret_uid) // Secret UID in Z
    ldi r31, hi8(secret_uid)
    
    ldi r20, 4      // Helper loop counter
    
uid_loop:
    ld r18, X+
    ld r19, Z+
    cp r18, r19
    brne not_match
    dec r20
    brne uid_loop
    
    rjmp match      // If we fall through, it's a match
