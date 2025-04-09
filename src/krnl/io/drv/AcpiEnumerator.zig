const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const Irp = @import("../Irp.zig");
const ob = @import("../../objects/ob.zig");
const io = @import("../io.zig");
const std = @import("std");
const util = @import("util");
const zuacpi = @import("zuacpi");
const uacpi = zuacpi.uacpi;
const ns = uacpi.namespace;
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
        .hardware_ids = &.{"ACPI_HAL\\PNP0C08"},
        .compatible_ids = &.{"PNP0C08"},
    };
    log.debug("registered acpi enumerating driver", .{});
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/acpi_sb");
}

fn load(_: *Driver, _: std.mem.Allocator) anyerror!?*Device {
    return null;
}

const AcpiBusExtension = struct {
    core: Device.DriverStackEntry,
    node: ?*uacpi.namespace.NamespaceNode,
};

fn attach(drv: *Driver, dev: *Device, alloc: std.mem.Allocator) anyerror!bool {
    log.debug("attaching acpi system board namespace", .{});
    const entry: *AcpiBusExtension = try alloc.create(AcpiBusExtension);

    const sb = ns.get_predefined(.sb);

    entry.* = .{
        .core = .{
            .driver = drv,
        },
        .node = sb,
    };
    dev.attach_bus(&entry.core);

    try recurse(drv, dev, alloc, sb);

    return true;
}

fn dispatch(_: *Driver, irp: *Irp) anyerror!Irp.InvocationResult {
    const sp: *AcpiBusExtension = @fieldParentPtr("core", irp.stack_position orelse return error.DriverExtensionMissing);

    switch (irp.parameters) {
        .enumeration => |e| switch (e) {
            .properties => |p| {
                if (UUID.eql(p.id, Device.Properties.known_properties.pci_downstream_segment)) {
                    if (sp.node == null) return error.Unsupported;
                    const seg: u16 = @truncate(uacpi.eval.eval_simple_integer(sp.node.?, "_SEG") catch |err| switch (err) {
                        error.NotFound => 0,
                        else => return err,
                    });
                    {
                        var tok: QueuedSpinLock.Token = undefined;
                        irp.device.props.bag_lock.lock(&tok);
                        defer tok.unlock();
                        _ = try irp.device.props.bag.getOrPutValue(irp.alloc, p.id, .{ .int = seg });
                    }
                    @as(*u16, @alignCast(@ptrCast(p.result))).* = seg;
                    return .complete;
                } else if (UUID.eql(p.id, Device.Properties.known_properties.pci_downstream_bus)) {
                    if (sp.node == null) return error.Unsupported;
                    const bbn: u8 = @truncate(uacpi.eval.eval_simple_integer(sp.node.?, "_BBN") catch |err| switch (err) {
                        error.NotFound => b: {
                            log.debug("no bbn found", .{});
                            break :b 0;
                        },
                        else => {
                            log.err("Error {} fetching BBN from ACPI", .{err});
                            return err;
                        },
                    });
                    {
                        var tok: QueuedSpinLock.Token = undefined;
                        irp.device.props.bag_lock.lock(&tok);
                        defer tok.unlock();
                        _ = try irp.device.props.bag.getOrPutValue(irp.alloc, p.id, .{ .int = bbn });
                    }
                    @as(*u8, @alignCast(@ptrCast(p.result))).* = @truncate(bbn);
                    return .complete;
                }

                return .pass;
            },
        },
    }
}

fn recurse(drv: *Driver, parent: *Device, alloc: std.mem.Allocator, node: *ns.NamespaceNode) !void {
    var iter: ?*ns.NamespaceNode = null;
    while (try ns.node_next_typed(node, &iter, .{ .device = true, .processor = true })) |n| {
        const dev = try descend(drv, parent, alloc, n);
        try recurse(drv, dev, alloc, n);
    }
}

noinline fn descend(drv: *Driver, parent: *Device, alloc: std.mem.Allocator, ns_node: *ns.NamespaceNode) !*Device {
    const dev: *Device = try alloc.create(Device);
    errdefer dev.deinit(alloc);
    dev.init(parent);
    const ext: *AcpiBusExtension = try alloc.create(AcpiBusExtension);
    ext.* = .{
        .core = .{
            .driver = drv,
        },
        .node = ns_node,
    };
    errdefer alloc.destroy(ext);
    ext.node = ns_node;
    dev.attach_bus(&ext.core);
    const info = try uacpi.utilities.get_namespace_node_info(ns_node);
    defer uacpi.utilities.free_namespace_node_info(info);

    if (info.typ == .processor) {
        dev.props.hardware_ids = try util.dupe_list(alloc, u8, &.{"ACPI\\ProcessorObject"});
        dev.props.compatible_ids = try util.dupe_list(alloc, u8, &.{"ACPI\\Processor"});

        if (ns_node.get_object()) |obj| {
            const i = try uacpi.object.get_processor_info(obj);
            try dev.props.bag.put(alloc, Device.Properties.known_properties.acpi_uid, .{ .str = try std.fmt.allocPrint(alloc, "{d}", .{i.id}) });
        } else {
            return error.AcpiObjectNotFound;
        }
    } else {
        if (info.flags.has_hid) {
            dev.props.hardware_ids = try util.dupe_list(alloc, u8, &.{info.hid.str_const()});
        }
        if (info.flags.has_cid) {
            dev.props.compatible_ids = try info.cid.dupe(alloc);
        }

        {
            if (try uacpi.resources.get_current_resources(ns_node)) |uacpi_resources| {
                defer uacpi_resources.deinit();
                var iterator = uacpi_resources.iterator();
                while (iterator.next()) |res| {
                    log.debug("uacpi resource: {}", .{res});
                    switch (res) {
                        .io => |ports| {
                            const io_res = try io.resources.resource_pool.create();
                            io_res._ = .{
                                .ports = .{
                                    .start = ports.minimum,
                                    .len = ports.length,
                                },
                            };
                            dev.props.transient_resources.append(io_res);
                        },
                        else => {
                            log.warn("unimplemented resource type {s}", .{@tagName(res)});
                        },
                    }
                }
            }
        }
    }
    if (info.flags.has_adr) {
        dev.props.address = info.adr;
    }
    if (info.flags.has_uid) {
        try dev.props.bag.put(alloc, Device.Properties.known_properties.acpi_uid, .{ .str = try alloc.dupe(u8, info.uid.str_const()) });
    }

    if (try uacpi.eval.eval_simple_integer_optional(ns_node, "_BBN")) |bbn| {
        try dev.props.bag.put(alloc, Device.Properties.known_properties.pci_downstream_bus, .{ .int = bbn });
    }

    if (try uacpi.eval.eval_simple_integer_optional(ns_node, "_SEG")) |seg| {
        try dev.props.bag.put(alloc, Device.Properties.known_properties.pci_downstream_segment, .{ .int = seg });
    }

    const path = b: {
        const path = ns_node.generate_absolute_path() orelse break :b "";
        defer uacpi.namespace.free_absolute_path(path);
        break :b try alloc.dupe(u8, std.mem.span(path));
    };
    try dev.props.bag.put(alloc, Device.Properties.known_properties.acpi_path, .{ .str = path });
    b: {
        const adr_str = std.fmt.allocPrint(alloc, "{x}", .{info.adr}) catch break :b;
        defer alloc.free(adr_str);
        log.debug("ACPI bus enumerated device of {s} {?s} at path {s}", .{
            if (info.flags.has_hid) "hid" else if (info.flags.has_adr) "adr" else "unidentified kind",
            if (info.flags.has_hid) info.hid.str_const() else if (info.flags.has_adr) adr_str else null,
            path,
        });
    }

    try io.report_device(alloc, dev);

    return dev;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
