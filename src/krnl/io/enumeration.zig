const io = @import("io.zig");
const Dpc = @import("../dispatcher/Dpc.zig");
const Device = io.Device;
const Driver = io.Driver;
const std = @import("std");
const hal = @import("../hal/hal.zig");
const alloc = hal.arch.vmm.gpa.allocator();

fn schedule_id_load(device: *Device) void {
    @atomicStore(u8, &device.enumeration_state.left, 2, .release);
    Dpc.init_and_schedule(.p2, &populate_hid_dpc, .{ device, null, null }) catch @panic("Could not create DPC for hardware enumeration");
    Dpc.init_and_schedule(.p2, &populate_cid_dpc, .{ device, null, null }) catch @panic("Could not create DPC for hardware enumeration");
}

fn populate_hid_dpc(dpc: *Dpc, device: *Device, _: ?*anyopaque, _: ?*anyopaque) void {
    defer dpc.deinit();
    const irp: *io.Irp = .init(alloc, device, .{
        .enumeration = .{
            .properties = .{
                .hardware_ids = null,
            },
        },
    }) catch @panic("Could not create IRP for HID population");
    defer irp.deinit();
    switch (io.execute_irp(irp) catch |e| switch (e) {
        error.IrpNotHandled, error.NoDriver => return,
        else => std.debug.panic("IO: Unexpected error enumerating HID: {}", .{e}),
    }) {
        .complete => {
            device.props.hardware_ids = irp.parameters.enumeration.properties.hardware_ids;
        },
        .pending => @panic("UNIMPLEMENTED"),
        .pass => unreachable,
    }

    check_schedule_probe(device);
}

fn populate_cid_dpc(dpc: *Dpc, device: *Device, _: ?*anyopaque, _: ?*anyopaque) void {
    defer dpc.deinit();
    const irp: *io.Irp = .init(alloc, device, .{
        .enumeration = .{
            .properties = .{
                .compatible_ids = null,
            },
        },
    }) catch @panic("Could not create IRP for HID population");
    defer irp.deinit();
    switch (io.execute_irp(irp) catch |e| switch (e) {
        error.IrpNotHandled, error.NoDriver => return,
        else => std.debug.panic("IO: Unexpected error enumerating HID: {}", .{e}),
    }) {
        .complete => {
            device.props.compatible_ids = irp.parameters.enumeration.properties.compatible_ids;
        },
        .pending => @panic("UNIMPLEMENTED"),
        .pass => unreachable,
    }

    check_schedule_probe(device);
}

fn check_schedule_probe(device: *Device) void {
    if (@atomicRmw(u8, &device.enumeration_state.left, .Sub, 1, .acq_rel) == 1) {
        Dpc.init_and_schedule(.p2, &driver_probe_dpc, .{ device, null, null }) catch @panic("Could not create DPC for hardware enumeration");
    }
}

fn driver_probe_dpc(dpc: *Dpc, device: *Device, _: ?*anyopaque, _: ?*anyopaque) void {
    defer dpc.deinit();

    var needs_new_ids: bool = false;
    defer if (needs_new_ids) schedule_id_load(device) else schedule_bus_discovery(device);

    if (device.props.hardware_ids) |hids| {
        for (hids) |hid| {
            for (device.test_drivers.items, 0..) |drv, i| {
                if (std.mem.eql(u8, drv.supported_devices.hardware_id, hid)) {
                    s: switch (drv.attach(device, alloc) catch continue) {
                        .no_attach => continue,
                        .redo_id_fetch => {
                            needs_new_ids = true;
                            continue :s .attached;
                        },
                        .attached => device.test_drivers.swapRemove(i),
                    }
                }
            }
        }
    }
    if (device.props.compatible_ids) |cids| {
        for (cids) |cid1| {
            for (device.test_drivers.items, 0..) |drv, i| {
                for (drv.supported_devices.compatible_ids) |cid2| {
                    if (std.mem.eql(u8, cid2, cid1)) {
                        s: switch (drv.attach(device, alloc) catch continue) {
                            .no_attach => continue,
                            .redo_id_fetch => {
                                needs_new_ids = true;
                                continue :s .attached;
                            },
                            .attached => device.test_drivers.swapRemove(i),
                        }
                    }
                }
            }
        }
    }
}

fn schedule_bus_discovery(device: *Device) void {
    Dpc.init_and_schedule(.p2, &bus_discovery_dpc, .{ device, null, null }) catch @panic("Could not create DPC for hardware enumeration");
}

fn bus_discovery_dpc(dpc: *Dpc, device: *Device, _: ?*anyopaque, _: ?*anyopaque) void {
    defer dpc.deinit();
    const irp: *io.Irp = .init(alloc, device, .{
        .enumeration = .{
            .bus_children = null,
        },
    }) catch @panic("Could not create IRP for bus enumeration");
    defer irp.deinit();
    switch (io.execute_irp(irp) catch |e| switch (e) {
        error.IrpNotHandled, error.NoDriver => return,
        else => std.debug.panic("IO: Unexpected error enumerating HID: {}", .{e}),
    }) {
        .complete => {
            if (irp.parameters.enumeration.bus_children) |kids| {
                for (kids) |kid| {
                    schedule_id_load(kid);
                }
            }
        },
        .pending => @panic("UNIMPLEMENTED"),
        .pass => unreachable,
    }
}
