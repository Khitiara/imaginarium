ENTRY(__kstart)

PHDRS
{
    none      PT_NULL    FLAGS(0);
    init      PT_LOAD    FLAGS((1 << 2) | (1 << 1) | (1 << 0) /* Read | Write | Execute */);
    text      PT_LOAD    FLAGS((1 << 2) | (1 << 0) /* Readable | Executable */);
    stk       PT_LOAD    FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
    data      PT_LOAD    FLAGS((1 << 2) | (1 << 1) /* Readable | Writeable  */);
    rodata    PT_LOAD    FLAGS((1 << 2)            /* Readable */);
    dynamic   PT_DYNAMIC FLAGS((1 << 2)            /* Readable */);
    meta      PT_NOTE;
}


SECTIONS
{
    . = -2048M; /* ok, why isnt G an allowed suffix in linkerscript lmao */
    __base__          = .;
    . += 0x100000;

    __kernel_begin__ = .;
    __kernel_init_begin__ = .;
    .init . : {
        *(.init*)
    } :init

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

    . = ALIGN(4K);
    __kernel_init_end__ = .;

    __kernel_text_begin__ = .;
    .text . : {
        *(.text*)
        . = ALIGN(4K);
        __ap_trampoline_begin__ = .;
        KEEP(*(.ap_trampoline*));
        __ap_trampoline_end__ = .;
    } :text
    . = ALIGN(4K);
    __kernel_text_end__ = .;

    . = ALIGN(16K);
    . += 4K;

    .bss.stack (NOLOAD) : {
        . = ALIGN(16K);
        __bootstrap_stack_bottom__ = .;
        . += 64K;
        . = ALIGN(8);
        __bootstrap_stack_top__ = .;
    } :stk

    . += 4K;

    .rodata . : {
        *(.rodata*)
	    *(.eh_frame)
    } :rodata

    . = ALIGN(4K);
    .data . : {
        *(.data*)
        gdt = .;
        QUAD(0x0000000000000000); /* null */
        QUAD(0x00af9b000000ffff); /* 64-bit code */
        QUAD(0x00af93000000ffff); /* 64-bit data */
        QUAD(0x00affb000000ffff); /* usermode 64-bit code */
        QUAD(0x00aff3000000ffff); /* usermode 64-bit data */
        tss_ldt = .;
        . += 16;
    } :data

    .dynamic : { *(.dynamic) } :data :dynamic

    . = ALIGN(4K);

    .bss (NOLOAD) : {
        *(.bss*)
    }

    . = ALIGN(4K);
    __kernel_end__ = .;
    __kernel_phys_end__ = . - __base__;
    __kernel_length__ = . - __kernel_begin__;

    .notes : {
        *(.note*)
    } : meta
    .comments : {
        *(.comment*)
    } : meta
/*    /DISCARD/ : { *(.comment*) *(.note*) }*/
}
