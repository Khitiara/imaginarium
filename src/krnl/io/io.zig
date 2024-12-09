const std = @import("std");
const ob = @import("../objects/ob.zig");
const UUID = @import("zuid").UUID;
const util = @import("util");
const queue = util.queue;
const hal = @import("../hal/hal.zig");
const QueuedSpinLock = hal.QueuedSpinLock;

pub const Device = @import("Device.zig");
pub const Driver = @import("Driver.zig");
pub const Irp = @import("Irp.zig");

pub fn execute_irp(irp: *Irp) !Irp.InvocationResult {
    defer irp.stack_position = null;
    var entry: ?*Device.DriverStackEntry = irp.stack_position orelse irp.device.driver_stack.peek() orelse return error.NoDriver;
    while (entry) |e| : (entry = e.next()) {
        irp.stack_position = entry;
        switch (try e.driver.dispatch(irp)) {
            .complete, .pending => |r| return r,
            .pass => {},
        }
    }
    return error.IrpNotHandled;
}

pub var drivers_dir: *ob.Directory = undefined;
pub var devices_dir: *ob.Directory = undefined;

pub fn register_drivers(alloc: std.mem.Allocator) !void {
    drivers_dir = try .init(alloc);
    try ob.root.children.put(alloc, "/Drivers", &drivers_dir.header);

    devices_dir = try .init(alloc);
    try ob.root.children.put(alloc, "/Devices", &devices_dir.header);

    try @import("drv/RootBus.zig").register(alloc);
    try @import("drv/AcpiEnumerator.zig").register(alloc);
}

const DeviceQueue = queue.Queue(Device, "queue_hook");
const DriverQueue = queue.Queue(Driver, "queue_hook");

var driver_load_queue: DriverQueue = .{};
var driver_queue_lock: QueuedSpinLock = .{};

var enumeration_queue: DeviceQueue = .{};
var enumeration_queue_lock: QueuedSpinLock = .{};

// INTERNAL STATE. DO NOT USE OUTSIDE DEV ENUMERATION
pub var all_drivers: []*Driver = .{};

pub fn report_driver_for_load(drv: *Driver) void {
    var token: QueuedSpinLock.Token = undefined;
    driver_queue_lock.lock(&token);
    defer token.unlock();
    driver_load_queue.append(drv);
}

var uid_print_buf: [38]u8 = undefined;

var root_bus: *Device = undefined;

pub fn load_drivers(alloc: std.mem.Allocator) !void {
    {
        // FIXME: using internal state of directory object
        var token: QueuedSpinLock.Token = undefined;
        drivers_dir.lock.lock(&token);
        defer token.unlock();
        var lst: std.ArrayListUnmanaged(*Driver) = try .initCapacity(alloc, drivers_dir.children.count());
        for (drivers_dir.children.values()) |o| {
            if (o.kind != .driver) continue;
            lst.appendAssumeCapacity(@fieldParentPtr("header", o));
        }
        all_drivers = try lst.toOwnedSlice(alloc);
    }

    root_bus = try alloc.create(Device);
    root_bus.init(null);
    root_bus.props.hardware_ids = try util.dupe_list(u8, &.{"ROOT"});
    root_bus.props.compatible_ids = try util.dupe_list(u8, &.{"ROOT"});

    var token: QueuedSpinLock.Token = undefined;
    while (b: {
        driver_queue_lock.lock(&token);
        defer token.unlock();
        break :b driver_load_queue.clear();
    }) |head| {
        var node: ?*Driver = head;
        while (node) |n| : (node = DriverQueue.next(n)) {
            if (try n.load()) |root_device| {
                root_device.attach_parent(root_bus);
                report_device(alloc, root_device);
            }
        }
    }
}

pub fn report_device(alloc: std.mem.Allocator, dev: *Device) !void {
    if (@cmpxchgStrong(bool, &dev.queued_for_probe, false, true, .acq_rel, .acquire) != null) {
        @branchHint(.unlikely);
        return;
    }
    if (@cmpxchgStrong(bool, &dev.inserted_in_directory, false, true, .acq_rel, .acquire) == null) {
        @branchHint(.likely);
        try devices_dir.insert(alloc, &dev.header, try std.fmt.bufPrint(&uid_print_buf, "{{{s}}}", .{dev.header.id}));
    }
    var token: QueuedSpinLock.Token = undefined;
    enumeration_queue_lock.lock(&token);
    defer token.unlock();
    enumeration_queue.append(dev);
}
