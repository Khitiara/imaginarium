.extern __bootstrap_stack_top__
.extern __kstart2
.global __kstart
.type __kstart, @function
__kstart:
    cli
    leaq __bootstrap_stack_top__, %rsp
    pushq $0
    pushq $0
    xorq %rbp, %rbp
    jmp __kstart2