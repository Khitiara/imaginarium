const ob = @import("../objects/ob.zig");
const util = @import("util");
const std = @import("std");
const Device = @import("Device.zig");
const Irp = @import("Irp.zig");
const UUID = @import("zuid").UUID;

const Driver = @This();

pub const VTable = struct {
    /// Load the driver, possibly creating root-level device objects.
    load: *const fn (self: *Driver, alloc: std.mem.Allocator) anyerror!?*Device,

    /// Attach to a newly enumerated device's stack. return true if the device could be attached to,
    /// which should usually be the case since pnp ids were already checked by the enumerator.
    /// if child devices are detected (e.g. on a bus), then the device tree should be updated,
    /// basic properties like address, hid, cids, etc set on children if possible, and a call
    /// made to io.report_device. note that this function will still be called on a root device returned
    /// from load, and recursive enumeration of root devices (like the ACPI bus) should be performed
    /// in attach rather than load.
    attach: *const fn (self: *Driver, device: *Device, alloc: std.mem.Allocator) anyerror!bool,

    dispatch: *const fn (self: *Driver, irp: *Irp) anyerror!Irp.InvocationResult,

    deinit: *const fn (self: *Driver, alloc: std.mem.Allocator) void,
};

pub fn init_internal(self: *Driver) void {
    self.header = .{
        .id = UUID.new.v4(),
        .kind = .driver,
        .vtable = &obvtbl,
    };
}

pub fn load(self: *Driver, alloc: std.mem.Allocator) anyerror!?*Device {
    return try self.vtable.load(self, alloc);
}

pub fn dispatch(self: *Driver, irp: *Irp) anyerror!Irp.InvocationResult {
    return try self.vtable.dispatch(self, irp);
}

pub fn attach(self: *Driver, device: *Device, alloc: std.mem.Allocator) anyerror!bool {
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
    hardware_ids: []const []const u8,
    compatible_ids: []const []const u8,
},
queue_hook: util.queue.Node = .{},

pub const ObjectKind = ob.ObjectKind.driver;

pub const deinit = Deinit.deinit_outer;
