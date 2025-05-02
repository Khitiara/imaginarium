SECTIONS {
    . = -2048M;
    . += 0x80000;
    __common_begin__ = .;
    .shared . : {
        KEEP(*(.shared*));
    } :data

    . = ALIGN(64);

    .sbss (NOLOAD) :{
        KEEP(*(.sbss*));
    }
    __common_end__ = .;
}

