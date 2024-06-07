const std = @import("std");
const seg = @import("segmentation.zig");
const util = @import("util");
const masking = util.masking;

pub const DescriptorType = enum(u1) {
    system = 0,
    normal = 1,
};

pub const SystemDescriptorType = enum(u4) {
    ldt = 0x2,
    tss_avail = 0x9,
    tss_busy = 0xB,
    call_gate = 0xC,
    interrupt_gate = 0xE,
};

pub const SegmentDescriptor = packed struct(u64) {
    limit_low: u16 = 0,
    base_low: u24 = 0,
    subtype: packed union {
        normal: seg.SegmentTypeField,
        system: SystemDescriptorType,
    },
    type: DescriptorType,
    dpl: u2,
    present: bool,
    limit_high: u4 = 0,
    unused: u1 = 0,
    long_mode_code: bool,
    operation_size: bool,
    granularity: enum(u1) {
        byte_units = 0,
        page_units = 1,
    },
    base_mid: u8 = 0,

    pub fn set_base(self: *SegmentDescriptor, base: u32) void {
        self.base_low = @truncate(base);
        self.base_mid = @truncate(base >> 24);
    }

    pub fn set_limit(self: *SegmentDescriptor, limit: u20) void {
        self.limit_low = @truncate(limit);
        self.limit_high = @truncate(limit >> 16);
    }
};

pub const TssLdtUpperHalf = packed struct(u64) {
    base_upper: u32 = 0,
    _reserved: u32 = 0,
};

pub const TssLdt = extern struct {
    lower: SegmentDescriptor,
    upper: TssLdtUpperHalf = .{},

    pub fn set_base(self: *TssLdt, base: u64) void {
        self.lower.set_base(@truncate(base));
        self.upper.base_upper = @truncate(base >> 32);
    }

    pub fn set_limit(self: *TssLdt, limit: u20) void {
        self.lower.set_limit(limit);
    }
};

pub const TableRegister = extern struct {
    _unused1: u32 = 0,
    _unused2: u16 = 0,
    limit: u16,
    base: u64,
};

pub const Selector = packed struct(u16) {
    rpl: u2,
    ti: enum(u1) {
        gdt = 0,
        ldt = 1,
    } = .gdt,
    index: u13 = 0,

    pub fn get_relative_addr(self: Selector) u16 {
        return @as(u16, @bitCast(self)) & masking.makeTruncMask(Selector, .index) << 1;
    }
};

test {
    std.testing.refAllDecls(@This());
}
