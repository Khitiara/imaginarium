const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const Irp = @import("../Irp.zig");
const ob = @import("../../objects/ob.zig");
const io = @import("../io.zig");
const std = @import("std");
const util = @import("util");
const zuacpi = @import("zuacpi");
const uacpi = zuacpi.uacpi;
const ns = uacpi.ns;
const UUID = @import("zuid").UUID;
const log = std.log.scoped(.@"drv.acpi");
const QueuedSpinLock = @import("../../hal/QueuedSpinLock.zig");

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
        .hardware_ids = &.{"ROOT\\ACPI_HAL"},
        .compatible_ids = &.{ "ROOT\\ACPI_HAL", "ACPI_HAL" },
    };
    log.debug("registered acpi root driver", .{});
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/acpi");
}

fn load(_: *Driver, alloc: std.mem.Allocator) anyerror!?*Device {
    const acpi_bus = try alloc.create(Device);
    acpi_bus.init(null);
    acpi_bus.props.hardware_ids = try util.dupe_list(alloc, u8, &.{"ROOT\\ACPI_HAL"});
    acpi_bus.props.compatible_ids = try util.dupe_list(alloc, u8, &.{ "ROOT\\ACPI_HAL", "ACPI_HAL" });
    return acpi_bus;
}

fn attach(drv: *Driver, dev: *Device, alloc: std.mem.Allocator) anyerror!bool {
    log.debug("attaching acpi system board namespace", .{});
    const core: *Device.DriverStackEntry = try alloc.create(Device.DriverStackEntry);
    core.driver = drv;
    dev.attach_bus(core);

    // create a device object for _SB
    const sb = try alloc.create(Device);
    sb.init(dev);
    sb.props.hardware_ids = try util.dupe_list(alloc, u8, &.{"ACPI_HAL\\PNP0C08"});
    sb.props.compatible_ids = try util.dupe_list(alloc, u8, &.{"PNP0C08"});
    try io.report_device(alloc, sb);

    return true;
}

fn dispatch(_: *Driver, _: *Irp) anyerror!Irp.InvocationResult {
    return .pass;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}