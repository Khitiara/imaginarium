const main = @import("main.zig");
const arch = @import("arch.zig");

pub inline fn rm_seg(p: *const anyopaque) u16 {
    return @intCast((@intFromPtr(p) & 0xffff0) >> 4);
}

pub inline fn rm_ofs(p: *const anyopaque) u16 {
    return @intCast(@intFromPtr(p) & 0xf);
}

pub const RealModeRegs = extern struct {
    gs: u16 align(1),
    fs: u16 align(1),
    es: u16 align(1),
    ds: u16 align(1),
    eflags: arch.Flags align(1),
    ebp: u32 align(1),
    edi: u32 align(1),
    esi: u32 align(1),
    edx: u32 align(1),
    ecx: u32 align(1),
    ebx: u32 align(1),
    eax: u32 align(1),
};

pub extern fn rm_int(int: u8, out_regs: *align(1) RealModeRegs, in_regs: *align(1) RealModeRegs) callconv(arch.cc) void;
