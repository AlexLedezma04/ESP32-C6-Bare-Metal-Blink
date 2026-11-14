ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x40800000, LENGTH = 64K
}

SECTIONS
{
    /* Code. _start goes first, so it sits at the very beginning of RAM */
    .text : { KEEP(*(.text.init)) *(.text .text.*) } > RAM

    /* Constants and variables, placed right after the code */
    .data : { *(.rodata .rodata.*) *(.srodata .srodata.*) *(.data .data.*) *(.sdata .sdata.*) } > RAM

    /* The stack starts at the very end of RAM and grows downward */
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /* Throw away extra info we don't need */
    /DISCARD/ : { *(.eh_frame*) *(.riscv.attributes) *(.comment) }
}
