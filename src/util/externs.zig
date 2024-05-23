pub inline fn extern_address(comptime name: []const u8) usize {
    const a = "leaq " ++ name ++ ", %[out]";
    return asm (a
        : [out] "=r" (-> usize),
    );
}
