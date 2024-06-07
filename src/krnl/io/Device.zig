const ob = @import("../objects/ob.zig");
const Driver = @import("Driver.zig");
const util = @import("util");
const std = @import("std");
const atomic = std.atomic;

const Device = @This();

header: ob.Object,
driver: *Driver,
hook: util.queue.Node = .{},
parent: ?*Device = null,
siblings: util.queue.DoublyLinkedNode = .{},
children: util.queue.DoublyLinkedList(Device, "siblings") = .{},
