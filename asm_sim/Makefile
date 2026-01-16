MCU=atmega328p
F_CPU ?= 16000000UL

TARGET ?= main
SRC=main.S

# On Windows, VS Code tasks may not inherit the MSYS2 PATH.
# Default to MSYS2 UCRT64 tool paths, but allow overriding from environment.
CC = C:/msys64/ucrt64/bin/avr-gcc.exe
OBJCOPY = C:/msys64/ucrt64/bin/avr-objcopy.exe

CFLAGS=-mmcu=$(MCU) -DF_CPU=$(F_CPU) -Os -Wall -Wextra -x assembler-with-cpp

all: $(TARGET).hex

# Convenience targets for Proteus clock mismatch debugging.
# Build one of these, then load the matching .hex in Proteus.
hex_16:
	$(MAKE) TARGET=main_16 F_CPU=16000000UL all

hex_12:
	$(MAKE) TARGET=main_12 F_CPU=12000000UL all

hex_11:
	$(MAKE) TARGET=main_11 F_CPU=11059200UL all

hex_8:
	$(MAKE) TARGET=main_8 F_CPU=8000000UL all

hex_1:
	$(MAKE) TARGET=main_1 F_CPU=1000000UL all

hex_all: hex_16 hex_12 hex_11 hex_8 hex_1

$(TARGET).elf: $(SRC)
	$(CC) $(CFLAGS) $^ -o $@

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex -R .eeprom $< $@

clean:
	cmd /c "del /q main*.elf main*.hex 2>nul"
