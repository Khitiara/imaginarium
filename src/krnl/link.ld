ENTRY(__kstart)

PHDRS
{
  none      PT_NULL FLAGS(0);
  text      PT_LOAD FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
  stk       PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  data      PT_LOAD FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
  rodata    PT_LOAD FLAGS((1 << 2)            /* Readable */);
  /*tls       PT_TLS  FLAGS((1 << 2) | (1 << 1) );*/
}


SECTIONS
{
    . = -2048M; /* ok, why isnt G an allowed suffix in linkerscript lmao */
    __base__          = .;
    . += 0x100000;

    __kernel_begin__ = .;
    __kernel_text_begin__ = .;
    .text . : {
        *(.text*)
        . = ALIGN(4K);
        __ap_trampoline_begin__ = .;
        KEEP(*(.ap_trampoline*));
        __ap_trampoline_end__ = .;
    }:text
    __kernel_text_end__ = .;

    . = ALIGN(16K);
    . += 16K;

    .bss.stack (NOLOAD) : {
        . = ALIGN(16K);
        __bootstrap_stack_bottom__ = .;
        . += 8M;
        . = ALIGN(8);
        __bootstrap_stack_top__ = .;
    } :stk

    . += 16K;
    .rodata . : {
        *(.rodata*)
    } :rodata

    . = ALIGN(8);
    .data . : {
        *(.data*)
    } :data

/*
    . = ALIGN(4K);
    __tls_start__ = .;
    __tls_data_start__ = .;
    .tdata . : {
        *(.tdata*)
    } : tls
    __tls_data_end__ = .;

    .tbss (NOLOAD) : {
        *(.tbss*)
    } : tls
    __tls_end__ = .;
 */

    . = ALIGN(4K);

    .bss (NOLOAD) : {
        *(.bss*)
    }

    . = ALIGN(4K);
    __kernel_end__ = .;
    __kernel_phys_end__ = . - __base__;

    /DISCARD/ : { *(.eh_frame*) *(.comment*) *(.note*) }
}
