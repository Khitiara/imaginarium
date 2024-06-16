    .balign 128
    .code16
    .org 0x8000
    .section .ap_trampoline
    .global ap_trampoline
ap_trampoline:
    cli
    cld
    ljmpw   $0, $0x8000 + (_trampoline_16 - ap_trampoline)
    .balign 16
_initial_gdt:
    .8byte 0
    .8byte 0x00A09A000000FFFF    // code64
    .8byte 0x008F92000000FFFF    // flat data32
_gdtr:
    .2byte   _gdtr - _initial_gdt - 1
    .4byte  0x8010
    .balign 64
_trampoline_16:
    xorw    %ax, %ax
    movw    %ax, %ds
    lgdtl   0x8000 + (_gdtr - ap_trampoline)
    movw    $16, %ax
    movw    %ax, %ds
    movw    %ax, %ss
    movl    $0x368, %eax
    movl    %eax, %cr4
    movl    (0x8000 + (_ap_cr3_ - ap_trampoline)), %eax
    movl    %eax, %cr3
    movl    $0x0C0000080, %ecx
    rdmsr
    orl     $0x100, %eax
    wrmsr
    movl    $0x0C0000011, %eax
    movl    %eax, %cr0
    ljmpl   $8, $0x8000 + (_trampoline_64 - ap_trampoline)
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
    pushq   (0x8000 + (_ap_stk_ - ap_trampoline))
    pushfq
    pushq   $8
    pushq   (0x8000 + (_ap_land_ - ap_trampoline))
    iretq
.balign 16
.global _ap_cr3
_ap_cr3_:
    .4byte   0, 0
.balign 16
.global _ap_stk
_ap_stk_:
    .4byte   0, 0
.balign 16
.global _ap_land
_ap_land_:
    .4byte   0, 0
.section text