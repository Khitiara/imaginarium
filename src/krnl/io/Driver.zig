const ob = @import("../objects/ob.zig");
const util = @import("util");
const std = @import("std");
const Device = @import("Device.zig");
const Irp = @import("Irp.zig");
const UUID = @import("zuid").UUID;

const Driver = @This();

pub const VTable = struct {
    /// Load the driver, possibly creating root-level device objects.
    load: *const fn (self: *Driver, alloc: std.mem.Allocator) InitError!?*Device,

    /// Attach to a newly enumerated device's stack
    attach: *const fn (self: *Driver, device: *Device, alloc: std.mem.Allocator) ProbeError!AttachResult = &no_attach,

    dispatch: *const fn (self: *Driver, irp: *Irp) DispatchError!Irp.InvocationResult,

    deinit: *const fn (self: *Driver, alloc: std.mem.Allocator) void,
};

fn no_attach(_: *Driver, _: *Device, _: std.mem.Allocator) ProbeError!AttachResult {
    return .no_attach;
}

pub const InitError = error{} || std.mem.Allocator.Error;
pub const ProbeError = error{Unsupported} || std.mem.Allocator.Error;
pub const DispatchError = error{ Unsupported, IrpNotHandled, NoDriver } || std.mem.Allocator.Error;

pub const AttachResult = enum {
    attached,
    redo_id_fetch,
    no_attach
};

pub fn init_internal(self: *Driver) void {
    self.header = .{
        .id = UUID.new.v4(),
        .kind = .driver,
        .vtable = &obvtbl,
    };
}

pub fn load(self: *Driver, alloc: std.mem.Allocator) !?*Device {
    return try self.vtable.load(self, alloc);
}

pub fn dispatch(self: *Driver, irp: *Irp) DispatchError!Irp.InvocationResult {
    return try self.vtable.dispatch(self, irp);
}

pub fn attach(self: *Driver, device: *Device, alloc: std.mem.Allocator) ProbeError!bool {
    return try self.vtable.attach(self, device, alloc);
}

const Deinit = ob.DeinitImpl(ob.Object, Driver, "header");

const obvtbl: ob.Object.VTable = .{
    .deinit = Deinit.deinit_inner,
};

header: ob.Object,
devices: util.queue.Queue(Device, "hook") = .{},
vtable: *const VTable,
supported_devices: struct {
    hardware_id: []const u8,
    compatible_ids: []const []const u8,
},
queue_hook: util.queue.Node = .{},

pub const ObjectKind = ob.ObjectKind.driver;

pub const deinit = Deinit.deinit_outer;
