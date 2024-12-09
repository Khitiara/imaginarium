.section .realmode

.global rm_hcf
rm_hcf: 
        # Load BIOS IVT
        lidt rm_hcf.rm_idt

        # Jump to real mode
        jmpl $0x08, $rm_hcf.bits16
    rm_hcf.bits16:
        movw $0x10,%ax
        movw %ax,%ds
        movw %ax,%es
        movw %ax,%fs
        movw %ax,%gs
        movw %ax,%ss
        movl %cr0, %eax
        btrw $0,%ax
        movl %eax, %cr0
        jmpl $0x00, $rm_hcf.cszero
    rm_hcf.cszero:
        xorw %ax,%ax
        movw %ax,%ds
        movw %ax,%es
        movw %ax,%fs
        movw %ax,%gs
        movw %ax,%ss

        sti
    rm_hcf.hang:
        hlt
        jmp rm_hcf.hang

    rm_hcf.rm_idt: .word 0x3ff
                   .long 0

.global rm_int
rm_int: 
        # Self-modifying code: int $int_no
        movb 4(%esp),%al
        movb %al, (rm_int.int_no)

        # Save out_regs
        movl 8(%esp),%eax
        movl %eax, (rm_int.out_regs)

        # Save in_regs
        movl 12(%esp),%eax
        movl %eax, (rm_int.in_regs)

        # Save GDT in case BIOS overwrites it
        sgdt rm_int.gdt

        # Save IDT
        sidt rm_int.idt

        # Load BIOS IVT
        lidt rm_int.rm_idt

        # Save non-scratch GPRs
        pushq %rbx
        pushq %rsi
        pushq %rdi
        pushq %rbp

        # Jump to real mode
        jmpl $0x08, $rm_int.bits16
[bits 16]
  rm_int.bits16: 
        movw $0x10,%ax
        movw %ax,%ds
        movw %ax,%es
        movw %ax,%fs
        movw %ax,%gs
        movw %ax,%ss
        movl %cr0, %eax
        andb $0xfe,%al
        movl %eax, %cr0
        jmpl $0x00, $rm_int.cszero
  rm_int.cszero: 
        xorw %ax,%ax
        movw %ax,%ss

        # Load in_regs
        movl %esp, %ss:rm_int.esp
        movl %ss:rm_int.in_regs, %esp
        popq %gs
        popq %fs
        popq %es
        popq %ds
        popfl
        popq %rbp
        popq %rdi
        popq %rsi
        popq %rdx
        popq %rcx
        popq %rbx
        popq %rax
        movl %ss:rm_int.esp,%esp

        sti

        # Indirect interrupt call
        .byte 0xcd
  rm_int.int_no: 
        .byte 0

        cli

        # Load out_regs
        movl %esp, %ss:rm_int.esp
        movl %ss:rm_int.out_regs,%esp
        leal 40(%esp),%esp
        pushq %rax
        pushq %rbx
        pushq %rcx
        pushq %rdx
        pushq %rsi
        pushq %rdi
        pushq %rbp
        pushfl
        pushq %ds
        pushq %es
        pushq %fs
        pushq %gs
        movl %ss:rm_int.esp,%esp

        # Restore GDT
        lgdt %ss:rm_int.gdt

        # Restore IDT
        lidt %ss:rm_int.idt

        # Jump back to pmode
        movl %cr0, %eax
        orb $1,%al
        movl %eax, %cr0
        jmpl $0x18, $rm_int.bits32
[bits 64]
  rm_int.bits32: 
        movw $0x20,%ax
        movw %ax,%ds
        movw %ax,%es
        movw %ax,%fs
        movw %ax,%gs
        movw %ax,%ss

        # Restore non-scratch GPRs
        popq %rbp
        popq %rdi
        popq %rsi
        popq %rbx

        # Exit
        ret

.align 16
  rm_int.esp: .long 0
  rm_int.out_regs: .long 0
  rm_int.in_regs: .long 0
  rm_int.gdt: .quad 0
  rm_int.idt: .quad 0
  rm_int.rm_idt: .word 0x3ff
                 .long 0

