ENTRY(_kstart)

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

    . = ALIGN(4K);                         /* bootstrap stack alloc */
    . += 4K;

    .bss.stack (NOLOAD) : {
        _bootstrap_stack = .;
        . += 8M;
        _bootstrap_stack_length = . - _bootstrap_stack;
    } :boot

    /DISCARD/ : { *(.eh_frame) *(.comment) }
}
