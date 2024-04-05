ENTRY(__kstart)

fb          = 0xffffffff800B8000;

/* initstack = 1024; */
PHDRS
{
  none   PT_NULL FLAGS(0);
  text   PT_LOAD FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
  stk    PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  data   PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  rodata PT_LOAD FLAGS((1 << 2)            /* Readable */);
}
SECTIONS
{
    . = 0xffffffff80100000;

    __kernel_begin = .;
    __kernel_text_begin = .;
    .text . : {
        *(.text*)
    }:text
    __kernel_text_end = .;

    . = ALIGN(64K);                         /* bootstrap stack alloc */
    . += 64K;

    .bss.stack (NOLOAD) : {
        . = ALIGN(64K);
        __bootstrap_stack_bottom = .;
        . += 8M;
        . = ALIGN(8);
        __bootstrap_stack_top = .;
    } :stk

    . += 64K;
    .rodata . : {
        *(.rodata*)
    } :rodata

    .data . : {
        *(.data*)
    } :data

    .bss (NOLOAD) : {
        *(.bss*)
    }

    /DISCARD/ : { *(.eh_frame) *(.comment) }
}
