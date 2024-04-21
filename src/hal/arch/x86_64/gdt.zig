const desc = @import("descriptors.zig");
const SentinelArrayBitSet = @import("util").sentinel_bit_set.SentinelArrayBitSet;
const std = @import("std");

pub const Gdt = extern struct {
    null_desc: u64,
    kernel_code: desc.SegmentDescriptor,
    kernel_data: desc.SegmentDescriptor,
    user_code: desc.SegmentDescriptor,
    user_data: desc.SegmentDescriptor,
    task_state: desc.TssLdt,
};

pub const Segment = std.meta.FieldEnum(Gdt);

export var gdt: Gdt = undefined;

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

pub const selectors = std.enums.EnumFieldStruct(Segment, desc.Selector, null){
    .null_desc = @bitCast(@as(u16, 0)),
    .kernel_code = .{
        .rpl = 0,
        .ti = .gdt,
        .index = 1,
    },
    .kernel_data = .{
        .rpl = 0,
        .ti = .gdt,
        .index = 2,
    },
    .user_code = .{
        .rpl = 3,
        .ti = .gdt,
        .index = 3,
    },
    .user_data = .{
        .rpl = 3,
        .ti = .gdt,
        .index = 4,
    },
    .task_state = .{
        .rpl = 0,
        .ti = .gdt,
        .index = 5,
    },
};

pub fn setup_gdt() void {
    tss = .{};
    tss.tss.iomap_offset = @offsetOf(TssBlock, "iomap") - @offsetOf(TssBlock, "tss");

    gdt.null_desc = 0;

    gdt.kernel_code = .{
        .type = .normal,
        .subtype = .{
            .normal = .{
                .type = .code,
                .flags = .{ .code = .{ .accessed = false, .readable = true, .conforming = false } },
            },
        },
        .dpl = 0,
        .present = true,
        .long_mode_code = true,
        .granularity = .byte_units,
        .operation_size = false,
    };
    gdt.kernel_code.set_limit(0xFFFFF);
    gdt.kernel_code.set_base(0);

    gdt.kernel_data = .{
        .type = .normal,
        .subtype = .{
            .normal = .{
                .type = .data,
                .flags = .{ .data = .{ .accessed = false, .writable = true, .expand_down = false } },
            },
        },
        .dpl = 0,
        .present = true,
        .long_mode_code = false,
        .granularity = .page_units,
        .operation_size = true,
    };
    gdt.kernel_data.set_limit(0xFFFFF);
    gdt.kernel_data.set_base(0);

    gdt.user_code = .{
        .type = .normal,
        .subtype = .{
            .normal = .{
                .type = .code,
                .flags = .{ .code = .{ .accessed = false, .readable = true, .conforming = false } },
            },
        },
        .dpl = 3,
        .present = true,
        .long_mode_code = true,
        .granularity = .byte_units,
        .operation_size = false,
    };
    gdt.user_code.set_limit(0xFFFFF);
    gdt.user_code.set_base(0);

    gdt.user_data = .{
        .type = .normal,
        .subtype = .{
            .normal = .{
                .type = .data,
                .flags = .{ .data = .{ .accessed = false, .writable = true, .expand_down = false } },
            },
        },
        .dpl = 3,
        .present = true,
        .long_mode_code = false,
        .granularity = .page_units,
        .operation_size = true,
    };
    gdt.user_data.set_limit(0xFFFFF);
    gdt.user_data.set_base(0);

    gdt.task_state = .{
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
    gdt.task_state.set_base(@intFromPtr(&tss));
    gdt.task_state.set_limit(@sizeOf(TssBlock) - 1);

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
}
