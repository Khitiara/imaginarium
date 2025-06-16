section .init
extern __bootstrap_stack_top__
extern __kstart2

global __kstart:function
__kstart:
    cli
    lea rsp, __bootstrap_stack_top__
    push qword 0
    push qword 0
    xor rbp, rbp
    jmp __kstart2