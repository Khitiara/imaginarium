const ob = @import("../objects/ob.zig");
const Driver = @import("Driver.zig");
const util = @import("util");
const std = @import("std");
const UUID = @import("zuid").UUID;
const atomic = std.atomic;

const Device = @This();

header: ob.Object,
driver: *Driver,
hook: util.queue.Node = .{},
parent: ?*Device,
siblings: util.queue.DoublyLinkedNode = .{},
children: util.queue.DoublyLinkedList(Device, "siblings") = .{},

pub fn init(self: *Device, driver: *Driver, parent: ?*Device, name: ?[]const u8) void {
    self.* = .{
        .header = .{
            .id = if (name) |n| b: {
                const ns = if (parent) |p| p.header.id else ob.namespace;
                break :b UUID.new.v5(ns, n);
            } else UUID.new.v4(),
            .kind = .device,
            .vtable = &vtable,
        },
        .driver = driver,
        .parent = parent,
    };
}

const vtable: ob.Object.VTable = .{
    .deinit = &deinit,
};

pub fn deinit(self: *Device, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
