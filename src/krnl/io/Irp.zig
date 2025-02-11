const std = @import("std");
const Device = @import("Device.zig");
const queue = @import("collections").queue;
const UUID = @import("zuid").UUID;

const Irp = @This();

/// the result of dispatching an Irp
pub const InvocationResult = enum {
    /// the Irp was fully completed Irp dispatch stops here
    complete,
    /// the Irp was partially handled but lower drivers may have more to do
    ///
    /// (e.g. resource enumeration where lower drivers may have additional resources not
    /// enumerable by the higher driver)
    ///
    /// if partial is returned by the last dispatch routine, complete is returned by io.execute_irp
    partial,
    /// the Irp is pending asynchronous completion, and either the completion callback or a dispatcher
    /// Event object will be signalled when the operation completes
    pending,
    /// the Irp could not be handled by the current driver but no error was generated, and lower
    /// drivers may be able to process the request. if pass is returned by the last dispatch routine,
    /// error.IrpNotHandled is returned by io.execute_irp
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
