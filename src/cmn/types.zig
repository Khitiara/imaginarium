const std = @import("std");
const builtin = @import("builtin");

pub const cc: std.builtin.CallingConvention = switch (builtin.target.cpu.arch) {
    .x86 => .{ .x86_sysv = .{} },
    .x86_64 => .{ .x86_64_sysv = .{} },
    else => |a| @compileError(std.fmt.comptimePrint("Unsupported imaginarium architecture {s}", .{@tagName(a)})),
};

pub const PhysAddr = enum(usize) {
    nul = 0,
    _,
    pub fn page(self: PhysAddr) u52 {
        return @intFromEnum(self) >> comptime std.math.log2(std.mem.page_size);
    }
};
pub const LinearAddr = usize;

pub const Flags = packed struct(usize) {
    carry: bool,
    _reserved1: u1 = 1,
    parity: bool,
    _reserved2: u1 = 0,
    aux_carry: bool,
    _reserved3: u1 = 0,
    zero: bool,
    sign: bool,
    trap: bool,
    interrupt_enable: bool,
    direction: bool,
    overflow: bool,
    iopl: u2,
    nt: bool,
    mode: bool,
    res: bool,
    vm: bool,
    alignment_check: bool,
    vif: bool,
    vip: bool,
    cpuid: bool,
    _reserved4: u8 = 0,
    aes_keyschedule_loaded: bool,
    alternate_instruction_set: bool,
    _padding: std.meta.Int(.unsigned, @bitSizeOf(usize) - 32) = 0,
};
