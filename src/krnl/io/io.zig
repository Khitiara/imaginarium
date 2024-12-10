const std = @import("std");
const ob = @import("../objects/ob.zig");
const UUID = @import("zuid").UUID;
const util = @import("util");
const queue = util.queue;
const hal = @import("../hal/hal.zig");
const QueuedSpinLock = hal.QueuedSpinLock;
const log = std.log.scoped(.io);

pub const Device = @import("Device.zig");
pub const Driver = @import("Driver.zig");
pub const Irp = @import("Irp.zig");

pub fn get_device_property(alloc: std.mem.Allocator, dev: *Device, id: UUID, ptr: anytype) !void {
    const irp: *Irp = try .init(alloc, dev, .{
        .enumeration = .{
            .properties = .{
                .id = id,
                .result = ptr,
            },
        },
    });
    defer irp.deinit();
    switch (try execute_irp(irp)) {
        .complete => {},
        .pending => @panic("UNIMPLEMENTED"),
        .pass => unreachable,
    }
}

pub fn execute_irp(irp: *Irp) !Irp.InvocationResult {
    defer irp.stack_position = null;
    var entry: ?*Device.DriverStackEntry = irp.stack_position orelse irp.device.driver_stack orelse return error.NoDriver;
    while (entry) |e| : (entry = e.next) {
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

    try @import("drv/AcpiEnumerator.zig").register(alloc);
    try @import("drv/PciBusEnumerator.zig").register(alloc);
}

const DeviceQueue = queue.Queue(Device, "queue_hook");
const DriverQueue = queue.Queue(Driver, "queue_hook");

var driver_load_queue: DriverQueue = .{};
var driver_queue_lock: QueuedSpinLock = .{};

var enumeration_queue: DeviceQueue = .{};
var enumeration_queue_lock: QueuedSpinLock = .{};

// INTERNAL STATE. DO NOT USE OUTSIDE DEV ENUMERATION
pub var all_drivers: []*Driver = undefined;

fn report_driver_for_load(drv: *Driver) void {
    var token: QueuedSpinLock.Token = undefined;
    driver_queue_lock.lock(&token);
    defer token.unlock();
    driver_load_queue.append(drv);
}

var uid_print_buf: [38]u8 = undefined;

var root_bus: *Device = undefined;

pub fn init(alloc: std.mem.Allocator) !void {
    try register_drivers(alloc);
    try load_drivers(alloc);
    try enumerate_devices(alloc);
}

pub fn load_drivers(alloc: std.mem.Allocator) !void {
    {
        // FIXME: using internal state of directory object
        var token: QueuedSpinLock.Token = undefined;
        drivers_dir.lock.lock(&token);
        defer token.unlock();
        var lst: std.ArrayListUnmanaged(*Driver) = try .initCapacity(alloc, drivers_dir.children.count());
        for (drivers_dir.children.values()) |o| {
            if (o.kind != .driver) continue;
            const d: *Driver = @fieldParentPtr("header", o);
            lst.appendAssumeCapacity(d);
        }
        all_drivers = try lst.toOwnedSlice(alloc);
    }

    root_bus = try alloc.create(Device);
    root_bus.init(null);
    root_bus.props.hardware_ids = try util.dupe_list(alloc, u8, &.{"ROOT"});
    root_bus.props.compatible_ids = try util.dupe_list(alloc, u8, &.{"ROOT"});
    _ = try devices_dir.insert(alloc, &root_bus.header, try std.fmt.bufPrint(&uid_print_buf, "{{{s}}}", .{root_bus.header.id}));

    for (all_drivers) |n| {
        if (try n.load(alloc)) |root_device| {
            root_device.attach_parent(root_bus);
            try report_device(alloc, root_device);
        }
    }
}

pub fn report_device(alloc: std.mem.Allocator, dev: *Device) !void {
    if (@cmpxchgStrong(bool, &dev.needs_driver, false, true, .acq_rel, .acquire) != null) {
        @branchHint(.unlikely);
        return;
    }
    if (@cmpxchgStrong(bool, &dev.inserted_in_directory, false, true, .acq_rel, .acquire) == null) {
        @branchHint(.likely);
        _ = try devices_dir.insert(alloc, &dev.header, try std.fmt.bufPrint(&uid_print_buf, "{{{s}}}", .{dev.header.id}));
    }
    // log.debug("Device reported for load", .{});
    var token: QueuedSpinLock.Token = undefined;
    enumeration_queue_lock.lock(&token);
    defer token.unlock();
    enumeration_queue.append(dev);
}

pub fn enumerate_devices(alloc: std.mem.Allocator) !void {
    var token: QueuedSpinLock.Token = undefined;
    while (b: {
        enumeration_queue_lock.lock(&token);
        defer token.unlock();
        break :b enumeration_queue.clear();
    }) |head| {
        var node: ?*Device = head;
        while (node) |n| : (node = DeviceQueue.next(n)) {
            try find_driver(n, alloc);
        }
    }
}

fn find_driver(device: *Device, alloc: std.mem.Allocator) !void {
    if (device.props.hardware_ids) |hids| {
        for (hids) |hid| {
            for (all_drivers) |drv| {
                for (drv.supported_devices.hardware_ids) |hid2| {
                    if (std.mem.eql(u8, hid2, hid)) {
                        if (try drv.attach(device, alloc)) return;
                    }
                }
            }
        }
    }
    if (device.props.compatible_ids) |cids| {
        for (cids) |cid1| {
            for (all_drivers) |drv| {
                for (drv.supported_devices.compatible_ids) |cid2| {
                    if (std.mem.eql(u8, cid2, cid1)) {
                        if (try drv.attach(device, alloc)) return;
                    }
                }
            }
        }
    }
    @atomicStore(bool, &device.needs_driver, false, .release);
}
