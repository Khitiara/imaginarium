ENTRY(__kstart)

PHDRS
{
  none      PT_NULL FLAGS(0);
  init      PT_LOAD FLAGS((1 << 2) | (1 << 1) | (1 << 0) /* Read | Write | Execute */);
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

    __ldr_begin__ = .;
    __ldr_text_begin__ = .;
    .text . : {
        *(.realmode)
        *(.text*)
        . = ALIGN(4K);
        __ap_trampoline_begin__ = .;
        KEEP(*(.ap_trampoline*));
        __ap_trampoline_end__ = .;
    }:text
    __ldr_text_end__ = .;

    . = ALIGN(8);
    .limine . : {
        QUAD(0xf6b8f4b39de7d1ae);
        QUAD(0xfab91a6940fcb9cf);
        QUAD(0x785c6ed015d3e316);
        QUAD(0x181e920a7852b9d9);

        QUAD(0xf9562b2d5c95a6c8);
        QUAD(0x6a7b384944536bdc);
        QUAD(3);

        KEEP(*(.limine*));
        . = ALIGN(8);
        QUAD(0xadc0e0531bb10d03);
        QUAD(0x9572709f31764c62);
    } :init

    . = ALIGN(2K);

    .bss.stack (NOLOAD) : {
        . = ALIGN(2K);
        __bootstrap_stack_bottom__ = .;
        . += 2K;
        . = ALIGN(8);
        __bootstrap_stack_top__ = .;
    } :stk

    .rodata . : {
        *(.rodata*)
    } :rodata

    . = ALIGN(16);
    .data . : {
        *(.data*)
    } :data

    . = ALIGN(4K);

    .bss (NOLOAD) : {
        *(.bss*)
    }

    . = ALIGN(4K);
    __ldr_end__ = .;
    __ldr_phys_end__ = . - __base__;

    /DISCARD/ : { *(.eh_frame*) *(.comment*) *(.note*) }
}
