ZIG     ?= zig
PORT    ?= /dev/ttyACM0
ESPTOOL ?= $(if $(wildcard venv/bin/esptool),venv/bin/esptool,esptool)

.PHONY: build flash clear

build: blink.bin

blink.elf: main.zig linker.ld
	$(ZIG) build-exe main.zig -target riscv32-freestanding -mcpu generic_rv32+m+a+c \
		-O ReleaseSmall -fno-entry -T linker.ld --name blink.elf

blink.bin: blink.elf
	$(ESPTOOL) --chip esp32c6 elf2image --flash-mode dio --flash-freq 40m blink.elf -o blink.bin

flash: build
	$(ESPTOOL) --chip esp32c6 --port $(PORT) write-flash 0x0 blink.bin

clean:
	rm -f blink.elf blink.bin
