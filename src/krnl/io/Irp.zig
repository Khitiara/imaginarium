//! IO request packets, the managed infrastructure for passing io operations through a device stack with room
//! for compatible expansion. The core of an IRP is its Parameters, which specify what IO operation is to be
//! performed. A driver SHALL specify a dispatch routine in its vtable, which routine takes an IRP and returns
//! an InvocationResult.

const std = @import("std");
const Device = @import("Device.zig");
const queue = @import("collections").queue;
const UUID = @import("zuid").UUID;
const Event = @import("../thread/Event.zig");

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

/// Irp parameters, a union tagged by the major operation to be performed.
/// The innermost struct of the active tag(s) SHALL have fields sufficient to
/// include enough information for the driver to complete the IO request, and
/// fields sufficient to store or point to storage for any information returned
/// by the requested IO operation.
pub const Parameters = union(enum) {
    enumeration: union(enum) {
        properties: struct {
            id: UUID,
            result: *anyopaque,
        },
    },
};

const Dpc = @import("../dispatcher/Dpc.zig");

pub fn irp_callback_dpc(dpc: *Dpc, irp: *Irp, cb: *const fn (*Irp, ?*anyopaque) void, user_ctx: ?*anyopaque) void {
    dpc.deinit();
    cb(irp, user_ctx);
}

pub const IrpCompletion = union(enum) {
    /// a callback and context for asynchronous completion.
    /// the callback SHALL be executed by a DPC in lieu of APCs, using irp_callback_dpc
    callback: struct {
        routine: *const fn (*Irp, ?*anyopaque) void,
        ctx: ?*anyopaque,
    },
    /// an event for blocking completion, which SHALL be set (passing true for reset_irql)
    /// when the result of the IO request is completed.
    event: *Event,

    pub fn blocking() !IrpCompletion {
        return .{ .event = try irp_completion_event_pool.create() };
    }
};

var irp_completion_event_pool: std.heap.MemoryPool(Event) = .init(@import("../hal/mm/pool.zig").pool_allocator);

alloc: std.mem.Allocator,
device: *Device,
/// the current entry in the driver extra data stack
stack_position: ?*Device.DriverStackEntry = null,
/// a queue hook for storing deferrable IRPs
queue_hook: queue.DoublyLinkedNode = .{},
/// the request parameters
parameters: Parameters,
/// completion information for blocking or asynchronous completion
completion: IrpCompletion,

pub fn init(alloc: std.mem.Allocator, device: *Device, parameters: Parameters, completion: IrpCompletion) !*Irp {
    const irp = try alloc.create(Irp);
    irp.* = .{
        .alloc = alloc,
        .device = device,
        .parameters = parameters,
        .completion = completion,
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
    switch (self.completion) {
        .event => |e| {
            irp_completion_event_pool.destroy(e);
        },
        .callback => {},
    }
    self.alloc.destroy(self);
}
