    .balign 128
    .code16
    .org 0x8000
    .section .ap_trampoline
    .global ap_trampoline
ap_trampoline:
    cli
    cld
    ljmpw   $0, $8040
    .balign 16
_initial_gdt:
    .4byte 0, 0
    .4byte 0x0000FFFF, 0x00CF9A00    // flat code
    .4byte 0x0000FFFF, 0x008F9200    // flat data
    .4byte 0x00000068, 0x00CF8900    // tss, not used but required by VB's vt-x
_gdtr:
    .2byte   _gdtr - _initial_gdt - 1
    .4byte  0x8030
    .4byte  0, 0
    .balign 64
_trampoline_16:
    xorw    %ax, %ax
    movw    %ax, %ds
    lgdtl   0x8030
    movl    %cr0, %eax
    orl     $1, %eax
    movl    %eax, %cr0
    ljmpl   $8, $8060
    .balign 32
    .code32
_trampoline_32:
    movw    $16, %ax
    movw    %ax, %ds
    movw    %ax, %ss
    movl    $0x368, %eax
    movl    %eax, %cr4
    movl    (0x80C0), %eax
    movl    %eax, %cr3
    movl    $0x0C0000080, %ecx
    rdmsr
    orl     $0x100, %eax
    wrmsr
    movl    $0x0C0000011, %eax
    movl    %eax, %cr0
    lgdtl   0x8030
    movl    $0x80C8 - 8, %esp
    lret
    .balign 32
    .code64
_trampoline_64:
    movl    $16, %eax
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %ss
    movw    %ax, %fs
    movw    %ax, %gs
    pushq   $16
    pushq   (_ap_stk)
    pushfq
    pushq   $8
    pushq   (_ap_land)
    iret
.global _cr3_value
_ap_cr3:
    .4byte   0, 0x1000
.global _ap_stk
_ap_stk:
    .4byte   0, 0
.global _ap_land
_ap_land:
    .4byte   0, 0