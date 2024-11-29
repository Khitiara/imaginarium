const ob = @import("../objects/ob.zig");
const util = @import("util");
const std = @import("std");
const Device = @import("Device.zig");
const UUID = @import("zuid").UUID;

const Driver = @This();

pub const VTable = struct {
    /// Initialize the driver. May result in creating root-level device objects.
    init: *const fn (self: *Driver, alloc: std.mem.Allocator) InitError!void,
    /// Probe a physical device, possibly creating a new device wrapping
    /// the physical device with more specific functionality. An implementation
    /// should return false as quickly as possible if the device is not compatible
    /// with the drive (usually because it is an unrelated device).
    probe: *const fn (self: *Driver, physical_device: *Device, alloc: std.mem.Allocator) ProbeError!bool,

    deinit: *const fn (self: *Driver, alloc: std.mem.Allocator) void,
};

pub const InitError = error{} || std.mem.Allocator.Error;
pub const ProbeError = error{} || std.mem.Allocator.Error;

pub fn init_internal(self: *Driver) void {
    self.header = .{
        .id = UUID.new.v4(),
        .kind = .driver,
        .vtable = &obvtbl,
    };
}

const Deinit = ob.DeinitImpl(ob.Object, Driver, "header");

const obvtbl: ob.Object.VTable = .{
    .deinit = Deinit.deinit_inner,
};

header: ob.Object,
devices: util.queue.Queue(Device, "hook") = .{},
vtable: *const VTable,

pub const ObjectKind = ob.ObjectKind.driver;

pub const deinit = Deinit.deinit_outer;
