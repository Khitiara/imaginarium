const uacpi = @import("uacpi.zig");
const namespace = uacpi.namespace;
const arch = @import("../../arch/arch.zig");
const std = @import("std");

pub const InterruptModel = enum(u32) {
    pic = 0,
    ioapic = 1,
    iosapic = 2,
};

extern fn uacpi_set_interrupt_model(InterruptModel) callconv(arch.cc) uacpi.uacpi_status;

pub fn set_interrupt_model(model: InterruptModel) !void {
    try uacpi_set_interrupt_model(model).err();
}

pub const IdString = extern struct {
    size: u32,
    value: [*]u8,

    pub fn str(self: *IdString) [:0]u8 {
        return self.value[0..(self.size - 1) :0];
    }

    pub fn str_const(self: *const IdString) [:0]const u8 {
        return self.value[0..(self.size - 1) :0];
    }
};

pub const PnpIdList = extern struct {
    count: u32,
    size: u32,
    pub fn ids(self: *PnpIdList) []IdString {
        return @as([*]IdString, @ptrCast(@as([*]u8, @ptrCast(self)) + @sizeOf(PnpIdList)))[0..self.count];
    }
    pub fn dupe(self: *const PnpIdList, alloc: std.mem.Allocator) ![]const []const u8 {
        const slc = try alloc.alloc([]const u8, self.count);
        for(self.ids(), 0..) |s, i| {
            slc[i] = try alloc.dupe(u8, s.str_const());
        }
    }
};

pub const NamespaceNodeInfoFlags = packed struct(u8) {
    has_adr: bool,
    has_hid: bool,
    has_uid: bool,
    has_cid: bool,
    has_cls: bool,
    has_sxd: bool,
    has_sxw: bool,
    _: u1 = 0,
};

pub const NamespaceNodeInfo = extern struct {
    size: u32,
    name: [4]u8,
    typ: uacpi.ObjectType,
    params: u8,
    flags: NamespaceNodeInfoFlags,
    sxd: [4]u8,
    sxw: [5]u8,
    adr: u64,
    hid: IdString,
    uid: IdString,
    cls: IdString,
    cid: PnpIdList,
};

extern fn uacpi_free_namespace_node_info(info: *NamespaceNodeInfo) callconv(arch.cc) void;
pub const free_namespace_node_info = uacpi_free_namespace_node_info;

extern fn uacpi_get_namespace_node_info(node: *namespace.NamespaceNode, out_info: **NamespaceNodeInfo) callconv(arch.cc) uacpi.uacpi_status;
pub fn get_namespace_node_info(node: *namespace.NamespaceNode) !*NamespaceNodeInfo {
    const info: *NamespaceNodeInfo = undefined;
    try uacpi_get_namespace_node_info(node, &info).err();
    return info;
}
