.extern __bootstrap_stack_top__;
.extern __kstart2;
.global __kstart;
__kstart:
    cli
    leal __bootstrap_stack_top__, %esp
    pushl $0
    pushl $0
    xorl %ebp, %ebp
    jmp __kstart2