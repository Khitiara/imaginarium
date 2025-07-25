
export fn __kstart() callconv(.naked) noreturn {
    asm volatile (
        \\
        :
    : [kstart] "X" (&@import("root").kstart),
    );
}

pub fn platform_init() !void {

}