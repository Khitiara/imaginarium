comptime {
    asm (
        \\ .extern __bootstrap_stack_top;
        \\ .extern __kstart2;
        \\ .global __kstart;
        \\ .type __kstart, @function;
        \\ __kstart:
        \\    leaq __bootstrap_stack_top, %rsp
        \\    pushq $0
        \\    pushq $0
        \\    xorq %rbp, %rbp
        \\    jmp __kstart2
    );
}
