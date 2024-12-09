const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const Irp = @import("../Irp.zig");
const ob = @import("../../objects/ob.zig");
const std = @import("std");

drv: Driver,

const vtable: Driver.VTable = .{
    .load = &load,
    .deinit = &ob.DeinitImpl(Driver, @This(), "drv").deinit_inner,
    .dispatch = &dispatch,
};

const RootBusStackExtension = struct {
    stack: Device.DriverStackEntry,
    hid: []const u8,
    cids: []const []const u8,
};

pub fn register(alloc: std.mem.Allocator) !void {
    const d = try alloc.create(@This());
    d.drv.init_internal();
    d.drv.vtable = &vtable;
    d.drv.supported_devices = .{
        .hardware_id = "ROOT",
        .compatible_ids = &.{
            "ROOT",
        },
    };
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/root");
}

fn load(drv: *Driver, alloc: std.mem.Allocator) Driver.InitError!?*Device {
    // const this: *@This() = @fieldParentPtr("drv", self);
    const rootbus = try alloc.create(Device);
    rootbus.init(null);
    const acpi_markers: *RootBusStackExtension = try alloc.create(RootBusStackExtension);
    acpi_markers.stack.driver = drv;
    acpi_markers.hid = "ROOT";
    acpi_markers.cids = &.{"ROOT"};
    rootbus.attach_driver(&acpi_markers.stack);
    return rootbus;
}

fn dispatch(d: *Driver, irp: *Irp) Driver.DispatchError!Irp.InvocationResult {
    // const self: *@This() = @fieldParentPtr("drv", d);
    switch (irp.parameters) {
        .enumeration => |*enumeration| {
            switch (enumeration.*) {
                .properties => |*properties| {
                    const e: *RootBusStackExtension = @fieldParentPtr("stack", irp.stack_position.?);
                    switch (properties.*) {
                        .hardware_ids => |*hids| {
                            const strs = try irp.alloc.alloc([]const u8, 1);
                            strs[0] = try irp.alloc.dupe(u8, e.hid);
                            hids.* = strs;
                            return .complete;
                        },
                        .compatible_ids => |*cids| {
                            const strs = try irp.alloc.alloc([]const u8, e.cids.len);
                            for (0..e.cids.len) |i| {
                                strs[i] = try irp.alloc.dupe(u8, e.cids[i]);
                            }
                            cids.* = strs;
                            return .complete;
                        },
                        else => @panic("UNIMPLEMENTED"),
                    }
                },
                .bus_children => |*children| {
                    const kids = try irp.alloc.alloc(*Device, 1);
                    kids[0] = try irp.alloc.create(Device);
                    kids[0].init(irp.device);
                    const acpi_markers: *RootBusStackExtension = try irp.alloc.create(RootBusStackExtension);
                    acpi_markers.stack.driver = d;
                    acpi_markers.hid = "ROOT\\ACPI_HAL";
                    acpi_markers.cids = &.{ "ROOT\\ACPI_HAL", "ACPI_HAL" };
                    kids[0].attach_driver(&acpi_markers.stack);
                    children.* = kids;
                    return .complete;
                },
            }
        },
    }
    @panic("UNIMPLEMENTED");
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
