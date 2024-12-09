const UUID = @import("zuid").UUID;
const std = @import("std");
const util = @import("util");

const DeviceProperties = @This();

pub const dev_props_ns = UUID.deserialize("0269d673-5f45-4c15-909d-f625a37cbe9a") catch unreachable;
pub const ids_ns = UUID.new.v5(dev_props_ns, "IDs");

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
