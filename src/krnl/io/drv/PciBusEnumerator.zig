const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const Irp = @import("../Irp.zig");
const ob = @import("../../objects/ob.zig");
const io = @import("../io.zig");
const std = @import("std");
const util = @import("util");
const UUID = @import("zuid").UUID;
const mcfg = @import("../../hal/acpi/mcfg.zig");
const pci = @import("../../hal/pci/pci.zig");
const log = std.log.scoped(.@"drv.pci");

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
        .hardware_ids = &.{
            "PNP0A08",
        },
        .compatible_ids = &.{
            "PNP0A08",
            "PNP0A03",
            "PCI\\CC_0604",
        },
    };
    log.debug("registered pci enumerating driver", .{});
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/pci");
}

fn load(_: *Driver, _: std.mem.Allocator) anyerror!?*Device {
    return null;
}

fn attach(drv: *Driver, dev: *Device, alloc: std.mem.Allocator) anyerror!bool {
    defer io.resources.free(&dev.props.transient_resources);

    @atomicStore(bool, &dev.has_driver, true, .release);
    var seg: u16 = undefined;
    try io.get_device_property(alloc, dev, Device.Properties.known_properties.pci_downstream_segment, &seg);
    var bus: u8 = undefined;
    try io.get_device_property(alloc, dev, Device.Properties.known_properties.pci_downstream_bus, &bus);

    log.debug("attaching to pci bridge downstream bus {X:0>4}:{X:0>2}", .{ seg, bus });

    const bridge = for (mcfg.host_bridges) |*hb| {
        if (hb.segment_group == seg) break hb;
    } else null;

    {
        if (dev.props.hardware_ids) |hids| {
            for (hids) |hid| {
                if (std.mem.eql(u8, hid, "PNP0A08") or std.mem.eql(u8, hid, "PNP0A03")) {
                    const e: *PciBusExtension = try alloc.create(PciBusExtension);
                    e.* = .{
                        .core = .{
                            .driver = drv,
                        },
                        .addr = .{
                            .segment = seg,
                            .bus = bus,
                            .device = 0,
                            .function = 0,
                            .bridge = bridge,
                        },
                        .kind = .root_complex,
                    };
                    dev.attach_bus(&e.core);
                }
            }
        }
    }

    for (0..32) |d| {
        var multifunction: bool = false;

        if (!try enumerate_function(alloc, .{
            .segment = seg,
            .bus = bus,
            .device = @intCast(d),
            .function = 0,
            .bridge = bridge,
        }, drv, dev, &multifunction)) continue;

        if (multifunction) {
            for (1..8) |fnum| {
                _ = try enumerate_function(alloc, .{
                    .segment = seg,
                    .bus = bus,
                    .device = @intCast(d),
                    .function = @intCast(fnum),
                    .bridge = bridge,
                }, drv, dev, null);
            }
        }
    }
    return true;
}

const PciHeaderType = enum {
    general,
    pci_pci_bridge,
    pci_cardbus_bridge,
};

fn enumerate_function(
    gpa: std.mem.Allocator,
    adr: pci.PciBridgeAddress,
    drv: *Driver,
    dev: *Device,
    multifunction: ?*bool,
) !bool {
    const ids: [2]u16 = @bitCast(try pci.config_read_with_bridge(adr, 0x0, u32));
    if (ids[0] == 0xFFFF) {
        return false;
    }

    const props_adr = (@as(u32, adr.device) << 16) | @as(u32, adr.function);

    var peer: ?*Device = dev.children.peek_front();
    var found: bool = false;
    const d: *Device = while (peer) |p| : (peer = Device.SiblingList.next(p)) {
        if (p.props.address == props_adr) {
            log.debug("PCI found existing devobj for segment {d} bus {d} device {d} function {d}", .{ adr.segment, adr.bus, adr.device, adr.function });
            found = true;
            break p;
        }
    } else b: {
        // log.debug("PCI creating new devobj for segment {d} bus {d} device {d} function {d}", .{ seg, bus, device, function });
        const d1 = try gpa.create(Device);
        d1.init(dev);
        d1.props.address = props_adr;
        break :b d1;
    };
    d.props.address = props_adr;

    errdefer if (!found) d.deinit(gpa);

    const classes: [4]u8 = @bitCast(try pci.config_read_with_bridge(adr, 0x8, u32));
    const stuff: [4]u8 = @bitCast(try pci.config_read_with_bridge(adr, 0xC, u32));

    if (multifunction) |mf| {
        mf.* = stuff[2] & 0x80 != 0;
    }

    const e: *PciBusExtension = try gpa.create(PciBusExtension);
    errdefer gpa.destroy(e);
    e.* = .{
        .core = .{
            .driver = drv,
        },
        .addr = adr,
        .kind = .{ .location = @enumFromInt(stuff[2] & 0x7F) },
    };
    d.attach_bus(&e.core);

    {
        var lst: std.ArrayListUnmanaged([]const u8) = .{};
        defer lst.deinit(gpa);
        if (d.props.hardware_ids) |hids| {
            try lst.appendSlice(gpa, hids);
            gpa.free(hids);
        }
        try lst.ensureUnusedCapacity(gpa, 4);
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&REV_{X:0>2}", .{ ids[0], ids[1], classes[0] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}", .{ ids[0], ids[1] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&CC_{X:0>2}{X:0>2}{X:0>2}", .{ ids[0], ids[1], classes[3], classes[2], classes[1] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&CC_{X:0>2}{X:0>2}", .{ ids[0], ids[1], classes[3], classes[2] }));
        d.props.hardware_ids = try lst.toOwnedSlice(gpa);
    }

    {
        var lst: std.ArrayListUnmanaged([]const u8) = .{};
        defer lst.deinit(gpa);
        if (d.props.compatible_ids) |cids| {
            try lst.appendSlice(gpa, cids);
            gpa.free(cids);
        }
        try lst.ensureUnusedCapacity(gpa, 7);

        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&REV_{X:0>2}", .{ ids[0], ids[1], classes[0] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}", .{ ids[0], ids[1] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&CC_{X:0>2}{X:0>2}{X:0>2}", .{ ids[0], classes[3], classes[2], classes[1] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&CC_{X:0>2}{X:0>2}", .{ ids[0], classes[3], classes[2] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}", .{ids[0]}));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\CC_{X:0>2}{X:0>2}{X:0>2}", .{ classes[3], classes[2], classes[1] }));
        try lst.append(gpa, try std.fmt.allocPrint(gpa, "PCI\\CC_{X:0>2}{X:0>2}", .{ classes[3], classes[2] }));
        d.props.compatible_ids = try lst.toOwnedSlice(gpa);
    }

    log.debug("PCI enumerated at segment {d} bus {d} device {d} function {d}: class {x}:{x}:{x} devid {x:0>4}:{x:0>4}", .{
        adr.segment,
        adr.bus,
        adr.device,
        adr.function,
        classes[3],
        classes[2],
        classes[1],
        ids[0],
        ids[1],
    });

    // if (comptime log.enabled(.debug)) {
    //     const hids1 = if (d.props.hardware_ids) |hids| try std.mem.join(gpa, ", ", hids) else try gpa.dupe(u8, "");
    //     defer gpa.free(hids1);
    //     const cids = if (d.props.compatible_ids) |cids| try std.mem.join(gpa, ", ", cids) else try gpa.dupe(u8, "");
    //     defer gpa.free(cids);
    //     log.debug("PCI set props with HID [{s}] CIDS [{s}] ADR {?x}", .{ hids1, cids, d.props.address });
    // }

    try io.report_device(gpa, d);
    return true;
}

const PciBusExtension = struct {
    core: Device.DriverStackEntry,
    kind: union(enum) {
        root_complex,
        location: PciHeaderType,
    },
    addr: pci.PciBridgeAddress,
};

fn dispatch(_: *Driver, irp: *Irp) anyerror!Irp.InvocationResult {
    log.debug("pci bridge dispatch", .{});
    const sp: *PciBusExtension = @fieldParentPtr("core", irp.stack_position orelse return error.DriverExtensionMissing);

    switch (irp.parameters) {
        .enumeration => |e| switch (e) {
            .properties => |p| {
                if (UUID.eql(p.id, Device.Properties.known_properties.pci_downstream_segment)) {
                    const is_bridge = switch (sp.kind) {
                        .root_complex => true,
                        .location => |typ| typ == .pci_pci_bridge,
                    };
                    if (!is_bridge)
                        return .pass;
                    @as(*u16, @alignCast(@ptrCast(p.result))).* = sp.addr.segment;
                    return .complete;
                } else if (UUID.eql(p.id, Device.Properties.known_properties.pci_downstream_bus)) {
                    switch (sp.kind) {
                        .location => |typ| {
                            if (typ != .pci_pci_bridge)
                                return .pass;

                            @as(*u8, @alignCast(@ptrCast(p.result))).* = try pci.config_read_with_bridge(sp.addr, 0x19, u8);
                            return .complete;
                        },
                        .root_complex => {
                            @as(*u8, @alignCast(@ptrCast(p.result))).* = sp.addr.bus;
                            return .complete;
                        },
                    }
                }

                return .pass;
            },
        },
    }
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
