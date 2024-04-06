const std = @import("std");
const seg = @import("segmentation.zig");
const util = @import("util");
const masking = util.masking;

const DescriptorType = enum(u1) {
    normal = 0,
    system = 1,
};

const SystemDescriptorType = enum(u4) {
    ldt = 0x2,
    tss_avail = 0x9,
    tss_busy = 0xB,
    call_gate = 0xC,
    interrupt_gate = 0xE,
};

const SegmentDescriptor = packed struct(u64) {
    limit_low: u16,
    base_low: u24,
    subtype: packed union {
        normal: seg.SegmentTypeField,
        system: SystemDescriptorType,
    },
    type: DescriptorType,
    dpl: u2,
    present: bool,
    limit_high: u4,
    unused: u1 = 0,
    long_mode_code: bool,
    operation_size: bool,
    granularity: enum(u1) {
        byte_units = 0,
        page_units = 1,
    },
    base_mid: u8,
};

const TssLdtUpperHalf = packed struct(u64) {
    base_upper: u32,
    _reserved: u32 = 0,
};

const GdtEntry = packed union {
    segment: SegmentDescriptor,
    upper: TssLdtUpperHalf,
};

const Gdtr = extern struct {
    _unused1: u32 = 0,
    _unused2: u16 = 0,
    limit: u16,
    base: u64,
};

const Selector = packed struct(u16) {
    rpl: u2,
    ti: enum(u1) {
        gdt = 0,
        ldt = 1,
    } = .gdt,
    index_upper: u12,

    pub fn get_index(self: Selector) u16 {
        return @as(u16, @bitCast(self)) & masking.makeTruncMask(Selector, .index_upper);
    }

    pub fn set_index(self: *Selector, index: u16) void {
        self.index_upper = @truncate(index >> 3);
    }
};

const InterruptGateDescriptor = packed struct(u128) {
    offset_low: u16,
    segment_selector: Selector,
    ist: u3,
    _reserved1: u5 = 0,
    type: enum(u4) {
        interrupt = 0xE,
        trap = 0xF,
        _,
    },
    _reserved2: u1 = 0,
    dpl: u2,
    present: u1,
    offset_upper: u48,
    _reserved3: u32 = 0,
};

test {
    std.testing.refAllDecls(@This());
}
