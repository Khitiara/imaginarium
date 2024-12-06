const arch = @import("../../arch/arch.zig");
const uacpi = @import("uacpi.zig");

pub const IterationDecision = enum(u32) {
    @"continue" = 0,
    @"break",
    next_peer,
};

pub const NamespaceNode = opaque {};

pub const IterationCallback = fn (user: ?*anyopaque, node: *NamespaceNode, depth: u32) callconv(arch.cc) IterationDecision;

extern fn uacpi_namespace_for_each_child_simple(parent: *NamespaceNode, cb: *const IterationCallback, user: ?*anyopaque) callconv(arch.cc) uacpi.uacpi_status;
pub fn for_each_child_simple(parent: *NamespaceNode, cb: *const IterationCallback, user: ?*anyopaque) !void {
    try uacpi_namespace_for_each_child_simple(parent, cb, user).err();
}

extern fn uacpi_namespace_for_each_child(
    parent: *NamespaceNode,
    descending_cb: *const IterationCallback,
    ascending_cb: *const IterationCallback,
    types: uacpi.ObjectTypeBits,
    max_depth: u32,
    user: ?*anyopaque,
) callconv(arch.cc) uacpi.uacpi_status;
pub fn for_each_child(parent: *NamespaceNode, descending_cb: *const IterationCallback, ascending_cb: *const IterationCallback, types: uacpi.ObjectTypeBits, max_depth: u32, user: ?*anyopaque) !void {
    try uacpi_namespace_for_each_child(parent, descending_cb, ascending_cb, types, max_depth, user).err();
}

pub const PredefinedNamespace = enum(u32) { root, gpe, pr, sb, si, tz, gl, os, osi, rev };

pub extern fn uacpi_namespace_get_predefined(ns: PredefinedNamespace) callconv(arch.cc) *NamespaceNode;
pub extern fn uacpi_namespace_root() callconv(arch.cc) *NamespaceNode;

pub extern fn uacpi_namespace_node_name(node: *const NamespaceNode) callconv(arch.cc) [4]u8;

pub extern fn uacpi_namespace_node_generate_absolute_path(node: *const NamespaceNode) callconv(arch.cc) ?[*:0]const u8;
pub extern fn uacpi_free_absolute_path(path: [*:0]const u8) callconv(arch.cc) void;

extern fn uacpi_namespace_node_type(node: *const NamespaceNode, out_type: *uacpi.ObjectType) callconv(arch.cc) uacpi.uacpi_status;
pub fn node_type(node: *const NamespaceNode) !uacpi.ObjectType {
    var typ: uacpi.ObjectType = undefined;
    try uacpi_namespace_node_type(node, &typ).err();
    return typ;
}
