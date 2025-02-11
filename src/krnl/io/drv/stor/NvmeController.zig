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
const log = std.log.scoped(.@"drv.stor.nvme");
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
        .hardware_ids = &.{},
        .compatible_ids = &.{"PCI\\CC_010802"},
    };
    log.debug("registered nvme controller driver", .{});
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/nvme");
}

fn load(_: *Driver, _: std.mem.Allocator) anyerror!?*Device {
    return null;
}

fn attach(drv: *Driver, dev: *Device, alloc: std.mem.Allocator) anyerror!bool {
    _ = drv; // autofix
    _ = dev; // autofix
    _ = alloc; // autofix
}

fn dispatch(_: *Driver, _: *Irp) anyerror!Irp.InvocationResult {
    return .pass;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
