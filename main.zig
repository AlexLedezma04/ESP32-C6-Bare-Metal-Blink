const LED_PIN = 8;
const WDT_KEY = 0x50D8_3AA1;

var COLOR_COUNTER: u8 = 0; // Based on the value, LED's color changes
const RED  = [_]u8{32, 0, 0};
const GREEN= [_]u8{0, 32, 0};
const BLUE = [_]u8{0, 0, 32};

// Hardware Low Addresses
const GPIO = 0x6009_1000;     // General-Purpose Input/Output
const IO_MUX = 0x6009_0000;   // Input/Output Multiplexer
const PCR = 0x6009_6000;      // Pad Configuration Register
const RMT = 0x6000_6000;      // Remote Control Transceiver
const RMT_RAM = 0x6000_6400;  // RMT address of the specific block of RAM
const SYSTIMER = 0x6000_A000; // The hardware timekeeper of the chip

// Turns a memory address into a pointer
fn reg(addr: usize) *volatile u32 {
    return @ptrFromInt(addr);
}

// Watchdogs are a hardware component with a safety mechanism that resets the microcontroller in case of a error
fn feedWatchdogs() void {
    // Timer-group watchdogs (MWDT0 and MWDT1)
    for ([_]usize{ 0x6000_8000, 0x6000_9000 }) |timg| {
        reg(timg + 0x64).* = WDT_KEY; // Unlock
        reg(timg + 0x60).* = 1;       // Feed
        reg(timg + 0x64).* = 0;       // Lock
    }
    // Low-power watchdog (LP_WDT)
    reg(0x600B_1C18).* = WDT_KEY; // Unlock
    reg(0x600B_1C14).* = 1 << 31; // Feed
    reg(0x600B_1C18).* = 0;       // Lock
    // Super watchdog (SWD)
    reg(0x600B_1C20).* = WDT_KEY; // Unlock
    reg(0x600B_1C1C).* = 1 << 31; // Feed
    reg(0x600B_1C20).* = 0;       // Lock
}

// System timer: 16 ticks per microsecond.
// Basically reads the current time from the ESP32's hardware timer
fn ticks() u32 {
    reg(SYSTIMER + 0x04).* = 1 << 30;                  // Latch current value
    while (reg(SYSTIMER + 0x04).* & (1 << 29) == 0) {} // Wait until the value is ready
    return reg(SYSTIMER + 0x44).*;                     // Return the low 32 bits of the latched value once its ready
}

fn sleep(ms: u32) void {
    reg(SYSTIMER).* |= (1 << 31) | (1 << 30); // So basically power on the timer: bit 31 = clock, bit 30 = counter 0
    const start = ticks();
    // 1 ms = 16000 ticks
    while (ticks() -% start < ms * 16_000) { // Once the value is greater than the specified ms, the loop ends
        feedWatchdogs(); // Indicates to the watchdogs that the process is correct, so it doesnt reset anything
    }
}

// RMT: 40 MHz clock, so 1 tick = 25 ns
// One RAM word describes one pulse: HIGH for a while, then LOW for a while
const LEVEL_HIGH: u32 = 1 << 15; // The first part of the pulse is HIGH

// Builds one pulse word from a high time and a low time (both in ticks)
fn pulse(high_ticks: u32, low_ticks: u32) u32 {
    return high_ticks | LEVEL_HIGH | (low_ticks << 16);
}

const BIT0 = pulse(16, 34); // 0.4 us high, 0.85 us low
const BIT1 = pulse(32, 18); // 0.8 us high, 0.45 us low

// Channel 0 settings
const DIVIDER_1: u32 = 1 << 8;    // don't slow the clock down
const MEM_1_BLOCK: u32 = 1 << 16; // use 1 block of RMT memory
const IDLE_OUT_EN: u32 = 1 << 6;  // hold the pin at the idle level when not sending (bit 5 left 0 = low)

const CH0_CONF = DIVIDER_1 | MEM_1_BLOCK | IDLE_OUT_EN;

// RMT channel 0 control register, and the commands you can send to it
const RMT_CTRL = RMT + 0x10;
const APPLY = 1 << 24;              // apply the settings just written
const START = 1;                    // start sending
const REWIND = (1 << 1) | (1 << 2); // go back to the first pulse in RMT RAM

// Changes only the bits in `mask` (sets them to `value`); all other bits stay as they were
fn setField(addr: usize, mask: u32, value: u32) void {
    const r = reg(addr);
    r.* = (r.* & ~mask) | value;
}

fn initLed() void {
    // Madness starts here, send RMT channel 0's signal (ID 71) to the LED pin, and make the pin an output
    reg(GPIO + 0x554 + LED_PIN * 4).* = 71 | (1 << 9);
    reg(GPIO + 0x24).* = 1 << LED_PIN;
    setField(IO_MUX + 0x04 + LED_PIN * 4, 0x7 << 12, 1 << 12); // pin function = normal GPIO
    // Turn on RMT's clock, driven by the 40 MHz crystal
    reg(PCR + 0x2C).* = 1;
    reg(PCR + 0x30).* = (3 << 20) | (1 << 22);
    reg(RMT + 0x68).* |= (1 << 31) | (1 << 26) | (1 << 1) | 1; // clocks on, direct RAM access, super obvious
    reg(RMT_CTRL).* = CH0_CONF | APPLY;
}

fn setLed(r: u32, g: u32, b: u32) void {
    const color = (g << 16) | (r << 8) | b; // the LED wants green, then red, then blue

    // Turn each of the 24 bits (leftmost first) into a pulse in RMT RAM
    for (0..24) |i| {
        const bit = (color >> @intCast(23 - i)) & 1;
        reg(RMT_RAM + i * 4).* = if (bit == 1) BIT1 else BIT0;
    }
    reg(RMT_RAM + 24 * 4).* = 0; // end marker
    reg(RMT_CTRL).* = CH0_CONF | REWIND | APPLY;
    reg(RMT_CTRL).* = CH0_CONF | START | APPLY;
}

fn startBlinks(counter: *u8) void {
    if(counter.* > 2) {counter.* = 0;}
    switch(counter.*){
        0 => setLed(RED[0], RED[1], RED[2]),
        1 => setLed(GREEN[0], GREEN[1], GREEN[2]),
        2 => setLed(BLUE[0], BLUE[1], BLUE[2]),
        else => setLed(0, 0, 0) // Turn off the LED if the counter breaks or something
    }
    sleep(1000);
    setLed(0, 0, 0);
    sleep(1000);
    counter.* += 1;
}

export fn main() noreturn {
    initLed();
    while (true) {
        startBlinks(&COLOR_COUNTER);
    }
}

// The chip starts running here (see ENTRY in linker.ld).
// No stack exists yet, so we can't run normal Zig code: set it up in assembly, then jump to main
export fn _start() linksection(".text.init") callconv(.naked) noreturn {
    asm volatile (
        \\ la sp, _stack_top  // point the stack pointer at the top of RAM (defined in linker.ld)
        \\ j  main            // jump to main (a jump, not a call: we never come back)
    );
}
