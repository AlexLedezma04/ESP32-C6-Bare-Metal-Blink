# ESP32-C6 LED RGB Blink

Bare-metal Zig blink for the ESP32-C6.

## Dependencies

- [Zig](https://ziglang.org/download/)
- Python 3 + [esptool](https://github.com/espressif/esptool) (in a venv)

## ESP32-C6 Documentation
- https://documentation.espressif.com/esp32-c6_technical_reference_manual_en.pdf

```sh
python3 -m venv venv
venv/bin/pip install esptool
```

## Build

```sh
make
```

## Flash

Plug in the board, then:

```sh
make flash
```

Default port is `/dev/ttyACM0`. Override with:

```sh
make flash PORT=/dev/ttyUSB0
```

## Clean

```sh
make clean
```
