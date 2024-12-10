const uacpi = @import("uacpi.zig");
const acpi = @import("../acpi.zig");
const arch = @import("../../arch/arch.zig");
const util = @import("util");
const namespace = @import("namespace.zig");

pub const ResourceType = enum(u32) {
    irq,
    extended_irq,

    dma,
    fixed_dma,

    io,
    fixed_io,

    addr16,
    addr32,
    addr64,
    addr64_extended,

    mem24,
    mem32,
    fixed_mem32,

    start_dependent,
    end_dependent,

    vendor_small,
    vendor_large,

    generic_register,
    gpio_connection,

    serial_i2c,
    serial_spi,
    serial_uart,
    serial_cs12,

    pin_function,
    pin_configuration,
    pin_group,
    pin_group_function,
    pin_group_configuration,

    clock_input,

    end_tag,
};

pub const LengthKind = enum(u8) {
    dont_care,
    one_less,
    full,
};
pub const Triggering = enum(u8) {
    level_triggered,
    edge_triggered,
};
pub const Polarity = enum(u8) {
    active_high,
    active_low,
    active_both,
};
pub const Sharing = enum(u8) {
    exclusive,
    shared,
};
pub const WakeCapability = enum(u8) {
    not_wake_capable,
    wake_capable,
};
pub const ResoruceSource = extern struct {
    index: u8,
    index_present: bool,
    length: u16,
    string: [*:0]u8,
};
pub const Irq = extern struct {
    length_kind: LengthKind,
    trigger: Triggering,
    polarity: Polarity,
    sharing: Sharing,
    wake_capability: WakeCapability,
    num_irqs: u8,
    pub fn irqs(self: *Irq) []u8 {
        return @as([*]u8, @ptrCast(self))[@sizeOf(Irq)..][0..self.num_irqs];
    }
};
pub const ExtendedIrq = extern struct {
    direction: u8,
    trigger: Triggering,
    polarity: Polarity,
    sharing: Sharing,
    wake_capability: WakeCapability,
    num_irqs: u8,
    source: ResoruceSource,
    pub fn irqs(self: *ExtendedIrq) []u32 {
        return @as([*]u32, @ptrCast(@as([*]u8, @ptrCast(self))[@sizeOf(ExtendedIrq)..]))[0..self.num_irqs];
    }
};
pub const TransferType = enum(u8) {
    eight_bit,
    eight_and_sixteen_bit,
    sixteen_bit,
};
pub const ChannelSpeed = enum(u8) {
    compatibility,
    type_a,
    type_b,
    type_f,
};
pub const TransferWidth = enum(u8) {
    @"8",
    @"16",
    @"32",
    @"64",
    @"128",
    @"256",
};
pub const Dma = extern struct {
    transfer_type: TransferType,
    bus_master_status: bool,
    channel_speed: ChannelSpeed,
    num_channels: u8,

    pub fn channels(self: *Dma) []u8 {
        return @as([*]u8, @ptrCast(self))[@sizeOf(Dma)..][0..self.num_irqs];
    }
};
pub const FixedDma = extern struct {
    request_line: u16,
    channel: u16,
    transfer_width: TransferWidth,
};
pub const DecodeType = enum(u8) {
    decode_10,
    decode_16,
};
pub const Io = extern struct {
    decode_type: DecodeType,
    minimum: u16,
    maximum: u16,
    alignment: u8,
    length: u8,
};
pub const FixedIo = extern struct {
    address: u16,
    length: u8,
};

pub const Resource: type = @Type(.{ .@"union" = .{
    .layout = .auto,
    .tag_type = ResourceType,
    .decls = &.{},
    .fields = b: {
        const f = @typeInfo(Resource).@"union".fields;
        var f2: [f.len]@import("std").builtin.Type.UnionField = undefined;
        for (0..f.len) |i| {
            const T = *f[i].type;
            f2[i] = .{
                .name = f[i].name,
                .alignment = @alignOf(T),
                .type = T,
            };
        }
        const f3 = f2;
        break :b &f3;
    },
} });

pub const ResourceNative = extern struct {
    typ: ResourceType,
    length: u32,
    resource: extern union {
        irq: Irq,
        extended_irq: ExtendedIrq,

        io: Io,
        fixed_io: FixedIo,
    },

    pub fn tagged(self: *ResourceNative) Resource {
        switch (self.typ) {
            inline else => |t| return @unionInit(Resource, @tagName(t), &@field(self.resource, @tagName(t))),
        }
    }
};

pub const Resources = extern struct {
    length: usize,
    entries: [*]u8, // actually a [*]ResourceNative but fucked up window struct indexer things apply

    pub fn indexer(self: *Resources) util.WindowStructIndexerMut(ResourceNative) {
        return util.WindowStructIndexerMut(ResourceNative){
            .buf = self.entries[0..self.length],
        };
    }

    pub fn slice(self: *Resources, buf: []*Resource) []*Resource {
        var idx = self.indexer();
        var cur: *ResourceNative = idx.current();
        var i: usize = 0;
        while (cur.typ != .end_tag) {
            buf[i] = cur.tagged();
            i += 1;
            idx.advance(cur.length);
            cur = idx.current();
        }
    }

    extern fn uacpi_free_resources(r: *Resources) callconv(arch.cc) void;
    pub const deinit = uacpi_free_resources;
};

extern fn uacpi_get_current_resources(n: *namespace.NamespaceNode, out_resources: **Resources) callconv(arch.cc) uacpi.uacpi_status;
pub fn get_current_resources(node: *namespace.NamespaceNode) !*Resources {
    var r: *Resources = undefined;
    try uacpi_get_current_resources(node, &r).err();
    return r;
}

comptime {
    @import("std").testing.refAllDeclsRecursive(@This());
}
