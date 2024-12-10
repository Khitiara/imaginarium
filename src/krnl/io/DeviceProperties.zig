const UUID = @import("zuid").UUID;
const std = @import("std");
const util = @import("util");

const DeviceProperties = @This();

pub const known_properties = struct {
    pub const pci_downstream_segment = UUID.deserialize("b017d0cd-fb23-43d4-bf6b-dfe3875a3b4e") catch unreachable;
    pub const pci_downstream_bus = UUID.deserialize("afc19b6b-30b0-4d15-81f3-a868fc101866") catch unreachable;
};

hardware_ids: ?[]const []const u8 = null,
compatible_ids: ?[]const []const u8 = null,
address: ?u64 = null,
bag: std.AutoArrayHashMapUnmanaged(UUID, union(enum) { int: u64, str: []const u8, multi_str: []const []const u8 }) = .{},

pub fn deinit(self: *const DeviceProperties, alloc: std.mem.Allocator) void {
    for (self.bag.items) |item| switch (item) {
        .str => |str| alloc.free(str),
        .multi_str => |multi| util.free_list(u8, multi),
        .int => {},
    };
    self.bag.deinit(alloc);

    if (self.hardware_ids) |hids| util.free_list(hids);
    if (self.compatible_ids) |cids| util.free_list(cids);
}