const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const ob = @import("../../objects/ob.zig");
const std = @import("std");

drv: Driver,

const vtable: Driver.VTable = .{
    .load = &load,
    .deinit = &ob.DeinitImpl(Driver, @This(), "drv").deinit_inner,
    .dispatch = undefined,
};

pub fn register(alloc: std.mem.Allocator) !void {
    const d = try alloc.create(@This());
    d.drv.init_internal();
    d.drv.vtable = &vtable;
    d.drv.supported_devices = .{
        .hardware_id = "ROOT\\ACPI_HAL",
        .compatible_ids = &.{ "ROOT\\ACPI_HAL", "ACPI_HAL" },
    };
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/acpi");
}

fn load(_: *Driver, _: std.mem.Allocator) Driver.InitError!?*Device {
    return null;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
