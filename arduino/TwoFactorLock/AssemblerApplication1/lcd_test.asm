; ATmega328P I2C LCD Test (AVRASM2)
; LCD backpack address: 0x27
; Wiring: SDA=PC4(A4), SCL=PC5(A5)

.equ __SFR_OFFSET = 0
.include "m328Pdef.inc"

.equ LCD_ADDR = 0x27
.equ LCD_BACKLIGHT = 0x08
.equ LCD_ENABLE = 0x04
.equ LCD_RS = 0x01

; TWI (I2C) Registers
.equ TWBR_REG = 0xB8
.equ TWSR_REG = 0xB9
.equ TWDR_REG = 0xBB
.equ TWCR_REG = 0xBC

; TWI Control Bits
.equ TWINT_BIT = 7
.equ TWSTA_BIT = 5
.equ TWSTO_BIT = 4
.equ TWEN_BIT = 2

.cseg
.org 0x0000
    rjmp RESET

RESET:
    ; Stack pointer init
    ldi     r16, HIGH(RAMEND)
    out     SPH, r16
    ldi     r16, LOW(RAMEND)
    out     SPL, r16

    ; Ensure SDA/SCL are inputs with pull-ups enabled
    cbi     DDRC, PC4
    cbi     DDRC, PC5
    sbi     PORTC, PC4
    sbi     PORTC, PC5

    rcall   i2c_init
    rcall   delay_50ms

    rcall   lcd_init
    rcall   lcd_clear

    ; Line 1
    ldi     r20, 0
    ldi     r21, 0
    rcall   lcd_set_cursor
    ldi     ZL, LOW(str_line1<<1)
    ldi     ZH, HIGH(str_line1<<1)
    rcall   lcd_print_string

    ; Line 2
    ldi     r20, 0
    ldi     r21, 1
    rcall   lcd_set_cursor
    ldi     ZL, LOW(str_line2<<1)
    ldi     ZH, HIGH(str_line2<<1)
    rcall   lcd_print_string

main_loop:
    rjmp    main_loop

; ---------------- I2C routines ----------------
i2c_init:
    ; 100kHz @ 16MHz CPU
    ldi     r16, 72
    sts     TWBR_REG, r16
    ldi     r16, 0
    sts     TWSR_REG, r16
    ldi     r16, (1<<TWEN_BIT)
    sts     TWCR_REG, r16
    ret

i2c_start:
    ldi     r16, (1<<TWINT_BIT)|(1<<TWSTA_BIT)|(1<<TWEN_BIT)
    sts     TWCR_REG, r16
i2c_start_wait:
    lds     r16, TWCR_REG
    sbrs    r16, TWINT_BIT
    rjmp    i2c_start_wait
    ret

i2c_stop:
    ldi     r16, (1<<TWINT_BIT)|(1<<TWSTO_BIT)|(1<<TWEN_BIT)
    sts     TWCR_REG, r16
    ret

i2c_write:
    ; Write byte in r24
    sts     TWDR_REG, r24
    ldi     r16, (1<<TWINT_BIT)|(1<<TWEN_BIT)
    sts     TWCR_REG, r16
i2c_write_wait:
    lds     r16, TWCR_REG
    sbrs    r16, TWINT_BIT
    rjmp    i2c_write_wait
    ret

; ---------------- LCD routines ----------------
lcd_init:
    rcall   delay_50ms

    ; 4-bit init sequence
    ldi     r24, 0x30
    rcall   lcd_send_nibble
    rcall   delay_5ms

    ldi     r24, 0x30
    rcall   lcd_send_nibble
    rcall   delay_1ms

    ldi     r24, 0x30
    rcall   lcd_send_nibble
    rcall   delay_1ms

    ldi     r24, 0x20
    rcall   lcd_send_nibble
    rcall   delay_1ms

    ; Function set: 4-bit, 2-line
    ldi     r24, 0x28
    rcall   lcd_send_command

    ; Display ON, cursor OFF
    ldi     r24, 0x0C
    rcall   lcd_send_command

    ; Clear
    ldi     r24, 0x01
    rcall   lcd_send_command
    rcall   delay_5ms

    ; Entry mode set
    ldi     r24, 0x06
    rcall   lcd_send_command
    ret

lcd_clear:
    ldi     r24, 0x01
    rcall   lcd_send_command
    rcall   delay_5ms
    ret

lcd_set_cursor:
    ; r20 = col, r21 = row
    mov     r24, r20
    tst     r21
    breq    lcd_cursor_set
    ori     r24, 0x40
lcd_cursor_set:
    ori     r24, 0x80
    rcall   lcd_send_command
    ret

lcd_print_string:
    ; Z points to null-terminated string in flash
    push    r24
lcd_ps_loop:
    lpm     r24, Z+
    tst     r24
    breq    lcd_ps_done
    rcall   lcd_send_data
    rjmp    lcd_ps_loop
lcd_ps_done:
    pop     r24
    ret

lcd_send_command:
    ; command byte in r24, RS=0
    push    r24
    push    r25
    mov     r25, r24

    andi    r24, 0xF0
    ori     r24, LCD_BACKLIGHT
    rcall   lcd_write_nibble_en

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
    ; data byte in r24, RS=1
    push    r24
    push    r25
    mov     r25, r24

    andi    r24, 0xF0
    ori     r24, LCD_BACKLIGHT|LCD_RS
    rcall   lcd_write_nibble_en

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
    ori     r24, LCD_BACKLIGHT
    rcall   lcd_write_nibble_en
    ret

lcd_write_nibble_en:
    ; nibble in upper bits of r24
    push    r24

    ; EN = 1
    ori     r24, LCD_ENABLE
    rcall   lcd_i2c_write_byte
    rcall   delay_1ms

    ; EN = 0
    pop     r24
    push    r24
    andi    r24, ~LCD_ENABLE
    rcall   lcd_i2c_write_byte
    rcall   delay_1ms

    pop     r24
    ret

lcd_i2c_write_byte:
    ; write r24 to LCD expander
    push    r24
    rcall   i2c_start

    ; 0x27 << 1 write
    ldi     r24, (LCD_ADDR<<1)
    rcall   i2c_write

    pop     r24
    rcall   i2c_write
    rcall   i2c_stop
    ret

; ---------------- Delays (16MHz) ----------------
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

delay_50ms:
    ldi     r22, 10
delay_50ms_loop:
    rcall   delay_5ms
    dec     r22
    brne    delay_50ms_loop
    ret

; ---------------- Strings ----------------
str_line1:
    .db "LCD TEST OK", 0
str_line2:
    .db "I2C ADDR 0x27", 0
