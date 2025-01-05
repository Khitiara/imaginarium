const desc = @import("descriptors.zig");
const SentinelArrayBitSet = @import("util").sentinel_bit_set.SentinelArrayBitSet;
const std = @import("std");

pub const Gdt = extern struct {
    null_desc: u64,
    kernel_code: desc.SegmentDescriptor,
    kernel_data: desc.SegmentDescriptor,
    user_code: desc.SegmentDescriptor,
    user_data: desc.SegmentDescriptor,
    tss: desc.TssLdt,
};

pub const Segment = std.meta.FieldEnum(Gdt);

extern const gdt: Gdt;
extern var tss_ldt: desc.TssLdt;

pub const Tss = extern struct {
    _reserved1: u32 = 0,
    rsp: [3]u64 align(4),
    ist: [8]u64 align(4),
    _reserved3: u64 align(4) = 0,
    _reserved4: u16 = 0,
    iomap_offset: u16 = @sizeOf(Tss),
};

pub fn IoPermissionBitMap(count: u32) type {
    return SentinelArrayBitSet(u8, count, 0xFF);
}

pub const IoMapType = IoPermissionBitMap(255);

pub const TssBlock = extern struct {
    tss: Tss = undefined,
    iomap: IoMapType = IoMapType.initEmpty(),
};

export var tss: TssBlock = undefined;

pub const selectors = struct {
    pub const null_desc: desc.Selector = @bitCast(@as(u16, 0));
    pub const kernel_code: desc.Selector = .{
        .rpl = 0,
        .ti = .gdt,
        .index = 1,
    };
    pub const kernel_data: desc.Selector = .{
        .rpl = 0,
        .ti = .gdt,
        .index = 2,
    };
    pub const user_code: desc.Selector = .{
        .rpl = 3,
        .ti = .gdt,
        .index = 3,
    };
    pub const user_data: desc.Selector = .{
        .rpl = 3,
        .ti = .gdt,
        .index = 4,
    };
    pub const tss: desc.Selector = .{
        .rpl = 0,
        .ti = .gdt,
        .index = 5,
    };
};

pub fn setup_gdt() void {
    tss = .{};
    tss.tss.iomap_offset = @offsetOf(TssBlock, "iomap") - @offsetOf(TssBlock, "tss");

    tss_ldt = .{
        .lower = .{
            .type = .system,
            .subtype = .{ .system = .tss_avail },
            .dpl = 0,
            .present = true,
            .long_mode_code = false,
            .granularity = .byte_units,
            .operation_size = false,
        },
        .upper = .{},
    };
    tss_ldt.set_base(@intFromPtr(&tss));
    tss_ldt.set_limit(@sizeOf(TssBlock) - 1);

    apply();
}

pub fn apply() void {
    const gdtr: desc.TableRegister = .{
        .base = @intFromPtr(&gdt),
        .limit = @sizeOf(Gdt) - 1,
    };
    asm volatile ("lgdt %[p]"
        :
        : [p] "*p" (&gdtr.limit),
    );

    asm volatile (
        \\ pushq %[csel]
        \\ leaq 1f(%%rip), %%rax
        \\ pushq %%rax
        \\ .byte 0x48, 0xCB // Far return
        \\ 1:
        :
        : [csel] "i" (@as(u16, @bitCast(selectors.kernel_code))),
        : "rax"
    );

    asm volatile (
        \\ mov %[dsel], %%ds
        \\ mov %[dsel], %%fs
        \\ mov %[dsel], %%gs
        \\ mov %[dsel], %%es
        \\ mov %[dsel], %%ss
        :
        : [dsel] "rm" (@as(u16, @bitCast(selectors.kernel_data))),
    );

    asm volatile ("ltr %[sel]"
        :
        : [sel] "r" (selectors.tss),
    );
}
