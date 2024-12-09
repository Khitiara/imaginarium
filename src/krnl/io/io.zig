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

// INTERNAL STATE. DO NOT USE OUTSIDE DEV ENUMERATION
pub var all_drivers: []*Driver = .{};

pub fn report_driver_for_load(drv: *Driver) void {
    var token: QueuedSpinLock.Token = undefined;
    driver_queue_lock.lock(&token);
    defer QueuedSpinLock.unlock(&token);
    driver_load_queue.append(drv);
}

pub fn load_drivers(alloc: std.mem.Allocator) !void {
    {
        // FIXME: using internal state of directory object
        var token: QueuedSpinLock.Token = undefined;
        drivers_dir.lock.lock(&token);
        defer QueuedSpinLock.unlock(&token);
        var lst: std.ArrayListUnmanaged(*Driver) = try .initCapacity(alloc, drivers_dir.children.count());
        for (drivers_dir.children.values()) |o| {
            if (o.kind != .driver) continue;
            lst.appendAssumeCapacity(@fieldParentPtr("header", o));
        }
        all_drivers = try lst.toOwnedSlice(alloc);
    }

    var uid_print_buf: [38]u8 = undefined;
    var token: QueuedSpinLock.Token = undefined;
    while (b: {
        driver_queue_lock.lock(&token);
        defer QueuedSpinLock.unlock(&token);
        break :b driver_load_queue.clear();
    }) |head| {
        var node: ?*Driver = head;
        while (node) |n| : (node = DriverQueue.next(n)) {
            if (try n.load()) |root_device| {
                try devices_dir.insert(alloc, &root_device.header, try std.fmt.bufPrint(&uid_print_buf, "{{{s}}}", .{root_device.header.id}));
                root_device.enumeration_state.test_drivers = .fromOwnedSlice(try alloc.dupe(*Driver, all_drivers));
            }
        }
    }
}
