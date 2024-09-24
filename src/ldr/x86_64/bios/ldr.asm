elf_load_base equ 0x8E00
ldr equ 0x7000

cpu x64
bits 16
org 0x7C00

%include "protocol.asm"

__start__:
ldrmain:
    jmp 0x0:.ldrmain2
.ldrmain2:
    xor bx, bx
    mov ds, bx
    mov ss, bx
    mov sp, ldrmain
    cld

block_size equ 0x200

.disk_read_loop:
    add word [dap.offset], block_size
    jnc .no_overflow
    add word [dap.segment], 0x1000
.no_overflow:
    sub dword [dap.remain], block_size
    jc .stopread
    inc dword [dap.lba]
    push dx
    mov ah, 0x42
    mov si, dap
    int 0x13
    pop dx
    ; Hey, that worked. Cool.
    ; Let's just continue reading until we hit some error.
    jnc .disk_read_loop

.stopread:
    mov di, 0x800
    xor al, al
    mov cx, 0x7C00 - 0x800
    rep stosb
    mov word [di], 0xa09a

    %include "memmap.asm"

dap:
    dw 16
    dw 1
    .offset: dw elf_load_base - block_size
    .segment: dw 0
    .lba: dq 0
    .remain: dd __end__ - __sector_end_marker__

times 0x200-($-$$) db 0
__sector_end_marker__:



__end__:
