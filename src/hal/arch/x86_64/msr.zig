const std = @import("std");

pub const Msr = enum(u32) {
    apic_base = 0x1B,
    pat = 0x277,
    efer = 0xC0000080,
    fs_base = 0xC000_0100,
    gs_base = 0xC000_0101,
    kernel_gs_base = 0xC000_0102,
};

const msr_writable = std.EnumArray(Msr, bool).initDefault(false, .{
    .apic_base = true,
    .efer = true,
});

const msr_readable = std.EnumArray(Msr, bool).initDefault(false, .{
    .apic_base = true,
    .efer = true,
});

fn MsrValueType(comptime msr: Msr) type {
    switch (msr) {
        .apic_base => return packed struct(u64) {
            _reserved1: u8 = 0,
            bsp: bool,
            _reserved2: u1 = 0,
            x2apic_enable: bool,
            apic_global_enable: bool,
            lapic_base: u52, // may need truncated to maxphyaddr
        },
        .efer => return packed struct(u64) {
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
        .fs_base, .gs_base, .kernel_gs_base => isize,
    }
}

fn isKnownMsr(msr: Msr) bool {
    return inline for (@typeInfo(Msr).Enum.fields) |f| {
        if (@intFromEnum(msr) == f.value) break true;
    } else false;
}

pub fn write(comptime msr: Msr, value: MsrValueType(msr)) void {
    if (!isKnownMsr(msr)) @compileError("Unknown MSR " ++ std.fmt.comptimePrint("0x{X}", @intFromEnum(msr)));
    if (!msr_writable.get(msr)) @compileError("Cannot write to read-only MSR " ++ @tagName(msr));

    const valueBytes: u64 = @bitCast(value);
    const low = @as(u32, @truncate(valueBytes));
    const high = @as(u32, @truncate(valueBytes >> 32));

    asm volatile ("wrmsr"
        :
        : [low] "{eax}" (low),
          [high] "{edx}" (high),
          [msr] "{ecx}" (@intFromEnum(msr)),
    );
}

pub fn read(comptime msr: Msr) MsrValueType(msr) {
    if (!isKnownMsr(msr)) @compileError("Unknown MSR " ++ std.fmt.comptimePrint("0x{X}", @intFromEnum(msr)));
    if (!msr_readable.get(msr)) @compileError("Cannot read to write-only MSR " ++ @tagName(msr));

    var low: u32 = undefined;
    var high: u32 = undefined;

    asm volatile ("rdmsr"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        : [msr] "{ecx}" (@intFromEnum(msr)),
    );

    return @bitCast([2]u32{ low, high });
}

test {
    _ = write;
    _ = read;
}
