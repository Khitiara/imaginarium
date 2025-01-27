const std = @import("std");
const Device = @import("Device.zig");
const queue = @import("collections").queue;
const UUID = @import("zuid").UUID;

const Irp = @This();

pub const InvocationResult = enum {
    complete,
    pending,
    pass,
};

pub const Function = enum {
    enumeration,
};

pub const Parameters = union(Function) {
    enumeration: union(enum) {
        properties: struct {
            id: UUID,
            result: *anyopaque,
        },
    },
};

alloc: std.mem.Allocator,
device: *Device,
stack_position: ?*Device.DriverStackEntry = null,
queue_hook: queue.SinglyLinkedNode = .{},
parameters: Parameters,
completion: ?struct {
    routine: *const fn (*Irp, ?*anyopaque) anyerror!void,
    ctx: ?*anyopaque,
} = null,

pub fn init(alloc: std.mem.Allocator, device: *Device, parameters: Parameters) !*Irp {
    const irp = try alloc.create(Irp);
    irp.* = .{
        .alloc = alloc,
        .device = device,
        .parameters = parameters,
    };
    return irp;
}

pub fn deinit(self: *Irp) void {
    switch (self.parameters) {
        .enumeration => |e| {
            switch (e) {
                .properties => {},
            }
        },
    }
    self.alloc.destroy(self);
}
