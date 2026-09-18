ENTRY(_start)

SECTIONS {
    . = 0x500;
    _stack_start = .;

    . = 0x7c00;
    _stack_end = .;
    _mbr_start = .;

    .text :
    {
        *(.text .text.*)
    }
    .rodata :
    {
        *(.rodata .rodata.*)
    }
    _mbr_end = .;

    . = 0x7c00 + 510;
    .magic_number :
    {
        SHORT(0xaa55)
    }

    . = 0x7E00 + (256 * 8) + 64;
    .data :
    {
        *(.data .data.*)
        *(.got .got.*)
        *(.eh_*)
    }
}