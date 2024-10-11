const std = @import("std");

pub const Msr = enum(u32) {
    apic_base = 0x1B,
    pat = 0x277,
    efer = 0xC0000080,
    fs_base = 0xC000_0100,
    gs_base = 0xC000_0101,
    kernel_gs_base = 0xC000_0102,
    _,
};

fn MsrValueType(comptime msr: Msr) type {
    return switch (msr) {
        .apic_base => packed struct(u64) {
            _reserved1: u8 = 0,
            bsp: bool,
            _reserved2: u1 = 0,
            x2apic_enable: bool,
            apic_global_enable: bool,
            lapic_base: u52, // may need truncated to maxphyaddr
        },
        .efer => packed struct(u64) {
            syscall_extensions: bool,
            _reserved1: u7 = 0,
            lme: bool,
            lma: bool,
            nxe: bool,
            svme: bool,
            lmsle: bool,
            ffxsr: bool,
            tce: bool,
            _reserved2: u48 = 0,
        },
        .pat => @import("paging/pat.zig").PAT,
        .fs_base, .gs_base, .kernel_gs_base => usize,
        _ => @panic(""),
    };
}

inline fn isKnownMsr(msr: Msr) bool {
    return inline for (@typeInfo(Msr).@"enum".fields) |f| {
        if (@intFromEnum(msr) == f.value) break true;
    } else false;
}

pub inline fn write_unsafe(msr: u32, value: u64) void {
    const low: u32 = @truncate(value);
    const high: u32 = @truncate(value >> 32);

    asm volatile ("wrmsr"
        :
        : [low] "{eax}" (low),
          [high] "{edx}" (high),
          [msr] "{ecx}" (msr),
    );
}

pub inline fn write(comptime msr: Msr, value: MsrValueType(msr)) void {
    if (!comptime isKnownMsr(msr)) {
        @compileError("Unknown MSR " ++ std.fmt.comptimePrint("0x{X}", .{@intFromEnum(msr)}));
    }

    write_unsafe(@intFromEnum(msr), @bitCast(value));
}

pub inline fn read_unsafe(msr: u32) u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;

    asm volatile ("rdmsr"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        : [msr] "{ecx}" (msr),
    );

    return (@as(u64, high) << 32) | low;
}

pub inline fn read(comptime msr: Msr) MsrValueType(msr) {
    if (!comptime isKnownMsr(msr)) {
        @compileError("Unknown MSR " ++ std.fmt.comptimePrint("0x{X}", @intFromEnum(msr)));
    }
    return @bitCast(read_unsafe(@intFromEnum(msr)));
}

test {
    _ = write;
    _ = read;
}
