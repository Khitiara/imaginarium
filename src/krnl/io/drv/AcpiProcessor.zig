const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const Irp = @import("../Irp.zig");
const ob = @import("../../objects/ob.zig");
const io = @import("../io.zig");
const std = @import("std");
const util = @import("util");
const uacpi = @import("../../hal/acpi/uacpi/uacpi.zig");
const zuacpi = @import("../../hal/acpi/zuacpi.zig");
const iter_passthru = @import("../../hal/acpi/zuacpi/iteration_error_passthrough.zig");
const UUID = @import("zuid").UUID;
const log = std.log.scoped(.@"drv.acpi_proc");
const QueuedSpinLock = @import("../../hal/QueuedSpinLock.zig");

const smp = @import("../../smp.zig");
const apic = @import("../../hal/apic/apic.zig");

drv: Driver,

const vtable: Driver.VTable = .{
    .load = &load,
    .attach = &attach,
    .deinit = &ob.DeinitImpl(Driver, @This(), "drv").deinit_inner,
    .dispatch = &dispatch,
};

pub fn register(alloc: std.mem.Allocator) !void {
    const d = try alloc.create(@This());
    errdefer d.deinit(alloc);
    d.drv.init_internal();
    d.drv.vtable = &vtable;
    d.drv.supported_devices = .{
        .hardware_ids = &.{ "ACPI0007", "ACPI\\ProcessorObject" },
        .compatible_ids = &.{"ACPI\\Processor"},
    };
    log.debug("registered acpi processor object driver", .{});
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/proc");
}

fn load(_: *Driver, _: std.mem.Allocator) anyerror!?*Device {
    return null;
}

fn attach(drv: *Driver, dev: *Device, alloc: std.mem.Allocator) anyerror!bool {
    var uid: []const u8 = undefined;
    io.get_device_property(alloc, dev, Device.Properties.known_properties.acpi_uid, &uid) catch |err| switch (err) {
        error.NotFound => {
            log.err("No APIC id in ACPI tables for processor device!", .{});
        },
        else => return err,
    };

    b: {
        var tok: QueuedSpinLock.Token = undefined;
        dev.props.bag_lock.lock(&tok);
        defer tok.unlock();
        const uid_int = try std.fmt.parseInt(u32, uid, 0);
        try dev.props.bag.put(alloc, Device.Properties.known_properties.processor_uid, .{ .int = uid_int });
        const lapic_id = for (apic.lapics.items(.uid), apic.lapics.items(.id)) |lapic_uid, lapic_id| {
            if (lapic_uid == uid_int) {
                break lapic_id;
            }
        } else {
            log.warn("Could not find LAPIC info for processor with UID {d}", .{uid_int});
            break :b;
        };
        log.debug("ACPI processor device registered for processor with ACPI uid {d}, LAPIC id {d}", .{ uid_int, lapic_id });
        try dev.props.bag.put(alloc, Device.Properties.known_properties.processor_apic_id, .{ .int = lapic_id });
        smp.prcbs[lapic_id].lcb.processor_device = dev;
    }

    const entry = try alloc.create(Device.DriverStackEntry);
    entry.* = .{
        .driver = drv,
    };
    dev.attach_driver(entry);

    return true;
}

fn dispatch(_: *Driver, _: *Irp) anyerror!Irp.InvocationResult {
    return .pass;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
