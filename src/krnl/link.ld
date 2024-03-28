ENTRY(_start)

fb          = 0xffffffff800B8000;

/* initstack = 1024; */
PHDRS
{
  boot PT_LOAD;                                /* one single loadable segment */
}
SECTIONS
{
    . = 0xffffffff80100000;

    .text : {
        KEEP(*(.text.boot)) *(.text .text.*)   /* code */
        *(.rodata .rodata.*)                   /* data */
        *(.data .data.*)
    } :boot
    
    .bss (NOLOAD) : {                          /* bss */
        . = ALIGN(16);
        *(.bss .bss.*)
        *(COMMON)
    } :boot

    /DISCARD/ : { *(.eh_frame) *(.comment) }
}
