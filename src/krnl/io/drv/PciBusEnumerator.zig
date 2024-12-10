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
    var seg: u16 = undefined;
    try io.get_device_property(alloc, dev, Device.Properties.known_properties.pci_downstream_segment, &seg);
    var bus: u8 = undefined;
    try io.get_device_property(alloc, dev, Device.Properties.known_properties.pci_downstream_bus, &bus);
    log.info("PCI attaching to segment {d} bus {d}", .{seg, bus});

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
                        .bus = bus,
                        .segment = seg,
                        .bus_location = .root_complex,
                        .bridge = bridge,
                    };
                    dev.attach_bus(&e.core);
                }
            }
        }
    }

    for (0..32) |d| {
        var multifunction: bool = false;
        if (!try enumerate_function(alloc, bridge, seg, drv, dev, bus, @intCast(d), 0, &multifunction)) continue;

        if (multifunction) {
            for (1..8) |fnum| {
                _ = try enumerate_function(alloc, bridge, seg, drv, dev, bus, @intCast(d), @intCast(fnum), null);
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
    bridge: ?*const mcfg.PciHostBridge,
    seg: u16,
    drv: *Driver,
    dev: *Device,
    bus: u8,
    device: u5,
    function: u3,
    multifunction: ?*bool,
) !bool {
    var adr: pci.PciAddress = .{
        .segment = seg,
        .bus = bus,
        .device = device,
        .function = function,
        .offset = 0,
    };

    const ids: [2]u16 = @bitCast(try pci.config_read_with_bridge(adr, bridge, u32));
    if (ids[0] == 0xFFFF) {
        return false;
    }

    const props_adr = (@as(u32, device) << 16) & @as(u32, function);

    var peer: ?*Device = dev.children.peek_front();
    const d: *Device = while (peer) |p| : (peer = Device.SiblingList.next(p)) {
        if (p.props.address == props_adr) {
            log.debug("PCI found existing devobj for segment {d} bus {d} device {d} function {d}", .{seg, bus, device, function});
            break p;
        }
    } else b: {
        log.debug("PCI creating new devobj for segment {d} bus {d} device {d} function {d}", .{seg, bus, device, function});
        const d1 = try gpa.create(Device);
        errdefer d1.deinit(gpa);
        d1.init(dev);
        try io.report_device(gpa, d1);
        d1.props.address = props_adr;
        break :b d1;
    };

    adr.offset = 8;
    const classes: [4]u8 = @bitCast(try pci.config_read_with_bridge(adr, bridge, u32));
    adr.offset = 12;
    const stuff: [4]u8 = @bitCast(try pci.config_read_with_bridge(adr, bridge, u32));

    if (multifunction) |mf| {
        mf.* = stuff[2] & 0x80 != 0;
    }

    const e: *PciBusExtension = try gpa.create(PciBusExtension);
    e.* = .{
        .core = .{
            .driver = drv,
        },
        .bus = bus,
        .segment = seg,
        .bridge = bridge,
        .bus_location = .{
            .location = .{
                .device = device,
                .function = function,
                .header_type = @enumFromInt(stuff[2] & 0x7F),
            },
        },
    };

    d.props.hardware_ids = try gpa.dupe([]const u8, &.{
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&REV_{X:0>2}", .{ ids[0], ids[1], classes[0] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}", .{ ids[0], ids[1] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&CC_{X:0>2}{X:0>2}{X:0>2}", .{ ids[0], ids[1], classes[3], classes[2], classes[1] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&CC_{X:0>2}{X:0>2}", .{ ids[0], ids[1], classes[3], classes[2] }),
    });
    d.props.compatible_ids = try gpa.dupe([]const u8, &.{
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}&REV_{X:0>2}", .{ ids[0], ids[1], classes[0] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&DEV_{X:0>4}", .{ ids[0], ids[1] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&CC_{X:0>2}{X:0>2}{X:0>2}", .{ ids[0], classes[3], classes[2], classes[1] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}&CC_{X:0>2}{X:0>2}", .{ ids[0], classes[3], classes[2] }),
        try std.fmt.allocPrint(gpa, "PCI\\VEN_{X:0>4}", .{ids[0]}),
        try std.fmt.allocPrint(gpa, "PCI\\CC_{X:0>2}{X:0>2}{X:0>2}", .{ classes[3], classes[2], classes[1] }),
        try std.fmt.allocPrint(gpa, "PCI\\CC_{X:0>2}{X:0>2}", .{ classes[3], classes[2] }),
    });

    return true;
}

const PciBusExtension = struct {
    core: Device.DriverStackEntry,
    segment: u16,
    bus: u8,
    bridge: ?*const mcfg.PciHostBridge,
    bus_location: union(enum) {
        root_complex,
        location: struct {
            header_type: PciHeaderType,
            device: u5,
            function: u3,
        },
    },
};

fn dispatch(_: *Driver, irp: *Irp) anyerror!Irp.InvocationResult {
    const sp: *PciBusExtension = @fieldParentPtr("core", irp.stack_position orelse return error.DriverExtensionMissing);

    switch (irp.parameters) {
        .enumeration => |e| switch (e) {
            .properties => |p| {
                if (UUID.eql(p.id, Device.Properties.known_properties.pci_downstream_segment)) {
                    switch (sp.bus_location) {
                        .location => |l| {
                            if (l.header_type != .pci_pci_bridge)
                                return .pass;

                            @as(*u16, @alignCast(@ptrCast(p.result))).* = sp.segment;
                            return .complete;
                        },
                        else => return .pass,
                    }
                } else if (UUID.eql(p.id, Device.Properties.known_properties.pci_downstream_bus)) {
                    switch (sp.bus_location) {
                        .location => |l| {
                            if (l.header_type != .pci_pci_bridge)
                                return .pass;

                            @as(*u8, @alignCast(@ptrCast(p.result))).* = try pci.config_read_with_bridge(.{
                                .segment = sp.segment,
                                .bus = sp.bus,
                                .device = l.device,
                                .function = l.function,
                                .offset = 0x19,
                            }, sp.bridge, u8);
                            return .complete;
                        },
                        else => return .pass,
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