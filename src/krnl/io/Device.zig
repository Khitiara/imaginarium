//! A logical device object, managed by one or more drivers

const ob = @import("../objects/ob.zig");
const Driver = @import("Driver.zig");
const util = @import("util");
const queue = util.queue;
const std = @import("std");
const UUID = @import("zuid").UUID;
const atomic = std.atomic;
pub const Properties = @import("DeviceProperties.zig");

const Device = @This();

/// an entry in the driver stack for this device. IO operations proceed down the stack,
/// with each driver able to either pass or handle a given operation/request, possibly
/// creating new requests to pass along (e.g. a file system driver may create a modified
/// request with file information and offsets converted to disk LBAs)
/// a driver will often use a custom struct for storing driver-specific device information
/// such as ACPI paths/node pointers, PCI config block pointers, etc., and use
/// @fieldParentPtr to retrieve the driver specific extension when processing an IO request
pub const DriverStackEntry = struct {
    /// the list entry for the driver stack. if the next entry in the driver stack for a
    /// device crosses a logical device boundary (e.g. volume to disk or disk to disk controller)
    /// then a new io request should be sent to a separate device object stored internally
    /// in the @fieldParentPtr extension of this stack entry
    next: ?*DriverStackEntry = null,
    prev: ?*DriverStackEntry = null,
    /// a list entry for hooking this stack entry into queues as needed internally
    queue_hook: queue.Node = .{},
    /// the driver which processes this entry in the driver stack
    driver: *Driver,
    device: *Device = undefined,
};

pub const SiblingList = queue.DoublyLinkedList(Device, "siblings");

header: ob.Object,
queue_hook: queue.DoublyLinkedNode = .{},
/// the driver stack for this device. drivers in the stack should use a @fieldParentPtr extension
/// of their DriverStackEntry to manage internal device state, and pass on any io request they
/// do not know how to handle. most devices will have one or two entries in the stack, but some
/// devices enumerated by multiple buses will have more, e.g. a UART connected directly to a PCI bus
/// with resources provided by ACPI will have an ACPI driver entry from initial enumeration, a
/// PCI driver entry from re-enumeration by the PCI bus, and a UART driver entry to perform actual
/// primary device functions
driver_stack: ?*DriverStackEntry = null,
bus_stack: ?*DriverStackEntry = null,

// device tree fields
parent: ?*Device = null,
children: SiblingList = .{},
siblings: queue.DoublyLinkedNode = .{},

// INTERNAL pnp enumeration state
find_driver_queued: bool = false,
inserted_in_directory: bool = false,
has_driver: bool = false,

// enumerated device properties
props: Properties = .{},

pub fn init(self: *Device, parent: ?*Device) void {
    self.* = .{
        .header = .{
            .id = UUID.new.v4(),
            .kind = .device,
            .vtable = &vtable,
        },
    };
    self.attach_parent(parent);
}

pub fn attach_parent(self: *Device, parent: ?*Device) void {
    if (self.parent) |p| {
        p.children.remove(self);
    }
    self.parent = parent;
    if (parent) |p| {
        p.children.add_back(self);
    }
}

pub fn attach_bus(self: *Device, entry: *DriverStackEntry) void {
    entry.device = self;

    if (self.bus_stack) |d| {
        // if there is a function driver stack, this makes sure the two are attached
        if (d.prev) |p| {
            entry.prev = p;
            p.next = entry;
        }
        // and stuff ourself on front
        d.prev = entry;
        entry.next = d;
    }
    // if theres no function stack then the whole stack should point to the function driver
    if (self.driver_stack == null) {
        self.driver_stack = entry;
    }
    self.bus_stack = entry;
}

pub fn attach_driver(self: *Device, entry: *DriverStackEntry) void {
    entry.device = self;

    if (self.driver_stack) |d| {
        d.prev = entry;
        entry.next = d;
    } else {
        entry.next = null;
    }
    self.driver_stack = entry;
}

const vtable: ob.Object.VTable = .{
    .deinit = &ob.DeinitImpl(ob.Object, Device, "header").deinit_inner,
};

pub fn deinit(self: *Device, alloc: std.mem.Allocator) void {
    if (self.parent) |p| {
        p.children.remove(self);
    }
    var kid = self.children.clear();
    while (kid) |k| : (kid = SiblingList.next(k)) {
        k.deinit(alloc);
    }
    alloc.destroy(self);
}
