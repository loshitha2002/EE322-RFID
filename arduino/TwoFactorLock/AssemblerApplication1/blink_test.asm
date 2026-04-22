; ATmega328P LED Blink Test (AVRASM2)
.equ __SFR_OFFSET = 0
.include "m328Pdef.inc"

.cseg
.org 0x0000
    rjmp RESET

RESET:
    ; Stack pointer
    ldi     r16, HIGH(RAMEND)
    out     SPH, r16
    ldi     r16, LOW(RAMEND)
    out     SPL, r16

    ; PB5 (D13) as output
    sbi     DDRB, DDB5

main_loop:
    ; LED ON
    sbi     PORTB, PORTB5
    rcall   delay_500ms

    ; LED OFF
    cbi     PORTB, PORTB5
    rcall   delay_500ms

    rjmp    main_loop

delay_1ms:
    push    r18
    push    r19
    ldi     r18, 21
    ldi     r19, 199
d1_loop:
    dec     r19
    brne    d1_loop
    dec     r18
    brne    d1_loop
    pop     r19
    pop     r18
    ret

delay_5ms:
    rcall   delay_1ms
    rcall   delay_1ms
    rcall   delay_1ms
    rcall   delay_1ms
    rcall   delay_1ms
    ret

delay_500ms:
    push    r20
    ldi     r20, 100
d500_loop:
    rcall   delay_5ms
    dec     r20
    brne    d500_loop
    pop     r20
    ret
