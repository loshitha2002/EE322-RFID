; ATmega328P ALL PINS SIMULTANEOUS BLINK TEST (AVRASM2)
; Tests all output pins used in main_final_real_lock_PC3_LOCK.asm at once
; If a pin doesn't blink at a probe location, that PCB trace is broken

.equ __SFR_OFFSET = 0
.include "m328Pdef.inc"

.cseg
.org 0x0000
    rjmp RESET

RESET:
    ; Stack pointer init
    ldi     r16, HIGH(RAMEND)
    out     SPH, r16
    ldi     r16, LOW(RAMEND)
    out     SPL, r16

    ; Configure all output pins
    ; PORTB: PB0, PB1, PB2, PB3, PB4, PB5 (all)
    ldi     r16, 0b00111111
    out     DDRB, r16

    ; PORTC: PC0, PC1, PC2, PC3, PC4, PC5 (all)
    ldi     r16, 0b00111111
    out     DDRC, r16

    ; PORTD: PD2, PD3, PD4, PD5, PD6, PD7
    ldi     r16, 0b11111100
    out     DDRD, r16

    ; All pins LOW initially
    ldi     r16, 0x00
    out     PORTB, r16
    out     PORTC, r16
    out     PORTD, r16

main_loop:
    ; ALL ON
    ldi     r16, 0b00111111
    out     PORTB, r16
    ldi     r16, 0b00111111
    out     PORTC, r16
    ldi     r16, 0b11111100
    out     PORTD, r16

    rcall   delay_500ms

    ; ALL OFF
    ldi     r16, 0x00
    out     PORTB, r16
    out     PORTC, r16
    out     PORTD, r16

    rcall   delay_500ms

    rjmp    main_loop

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

delay_500ms:
    ldi     r18, 100
delay_500ms_loop:
    rcall   delay_5ms
    dec     r18
    brne    delay_500ms_loop
    ret
