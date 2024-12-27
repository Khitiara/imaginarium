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
    log.debug("registered acpi enumerating driver", .{});
    try ob.insert(alloc, &d.drv.header, "/?/Drivers/acpi");
}

fn load(_: *Driver, alloc: std.mem.Allocator) anyerror!?*Device {
    const acpi_bus = try alloc.create(Device);
    acpi_bus.init(null);
    acpi_bus.props.hardware_ids = try util.dupe_list(alloc, u8, &.{"ROOT\\ACPI_HAL"});
    acpi_bus.props.compatible_ids = try util.dupe_list(alloc, u8, &.{ "ROOT\\ACPI_HAL", "ACPI_HAL" });
    return acpi_bus;
}

const AcpiBusExtension = struct {
    core: Device.DriverStackEntry,
    node: ?*uacpi.namespace.NamespaceNode,
};

fn attach(drv: *Driver, dev: *Device, alloc: std.mem.Allocator) anyerror!bool {
    log.debug("attaching acpi root bus", .{});
    const entry: *AcpiBusExtension = try alloc.create(AcpiBusExtension);
    entry.* = .{
        .core = .{
            .driver = drv,
        },
        .node = null,
    };
    dev.attach_bus(&entry.core);

    var ctx: EnumerationContext = .{
        .alloc = alloc,
        .drv = drv,
        .dev = dev,
    };
    var ctx2: AttachPassThru.IterationContext = .{
        .user = &ctx,
    };
    try uacpi.namespace.for_each_child(
        uacpi.namespace.get_root(),
        &AttachPassThru.create_callback(descend),
        &AttachPassThru.create_callback(ascend),
        .{
            .device = true,
            .processor = true,
        },
        std.math.maxInt(u32),
        &ctx2,
    );
    if (ctx2.err) |e| return e;

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

const EnumerationContext = struct {
    dev: *Device,
    drv: *Driver,
    alloc: std.mem.Allocator,
};
const AttachPassThru = iter_passthru.IterationErrorPasser(anyerror);

noinline fn descend(user: ?*anyopaque, ns_node: *uacpi.namespace.NamespaceNode, _: u32) anyerror!uacpi.namespace.IterationDecision {
    const ctx: *EnumerationContext = @alignCast(@ptrCast(user.?));
    const dev: *Device = try ctx.alloc.create(Device);
    errdefer dev.deinit(ctx.alloc);
    dev.init(ctx.dev);
    const ext: *AcpiBusExtension = try ctx.alloc.create(AcpiBusExtension);
    ext.* = .{
        .core = .{
            .driver = ctx.drv,
        },
        .node = ns_node,
    };
    errdefer ctx.alloc.destroy(ext);
    ext.node = ns_node;
    dev.attach_bus(&ext.core);
    const info = try uacpi.utilities.get_namespace_node_info(ns_node);
    defer uacpi.utilities.free_namespace_node_info(info);

    if (info.typ == .processor) {
        dev.props.hardware_ids = try util.dupe_list(ctx.alloc, u8, &.{"ACPI0007"});
        dev.props.compatible_ids = try util.dupe_list(ctx.alloc, u8, &.{"ACPI\\Processor"});
    } else {
        if (info.flags.has_hid) {
            dev.props.hardware_ids = try util.dupe_list(ctx.alloc, u8, &.{info.hid.str_const()});
        }
        if (info.flags.has_cid) {
            dev.props.compatible_ids = try info.cid.dupe(ctx.alloc);
        }
    }
    if (info.flags.has_adr) {
        dev.props.address = info.adr;
    }
    if (info.flags.has_uid) {
        try dev.props.bag.put(ctx.alloc, Device.Properties.known_properties.acpi_uid, .{ .str = try ctx.alloc.dupe(u8, info.uid.str_const()) });
        if (info.typ == .processor) {
            try dev.props.bag.put(ctx.alloc, Device.Properties.known_properties.processor_apic_id, .{ .str = try ctx.alloc.dupe(u8, info.uid.str_const()) });
        }
    }
    const path = b: {
        const path = uacpi.namespace.node_generate_absolute_path(ns_node) orelse break :b "";
        defer uacpi.namespace.free_absolute_path(path);
        break :b try ctx.alloc.dupe(u8, std.mem.span(path));
    };
    try dev.props.bag.put(ctx.alloc, Device.Properties.known_properties.acpi_path, .{ .str = path });
    b: {
        const adr_str = std.fmt.allocPrint(ctx.alloc, "{x}", .{info.adr}) catch break :b;
        defer ctx.alloc.free(adr_str);
        log.debug("ACPI bus enumerated device of {s} {?s} at path {s}", .{
            if (info.flags.has_hid) "hid" else if (info.flags.has_adr) "adr" else "unidentified kind",
            if (info.flags.has_hid) info.hid.str_const() else if (info.flags.has_adr) adr_str else null,
            path,
        });
    }
    ctx.dev = dev;
    try io.report_device(ctx.alloc, dev);
    return .@"continue";
}

noinline fn ascend(user: ?*anyopaque, _: *uacpi.namespace.NamespaceNode, _: u32) anyerror!uacpi.namespace.IterationDecision {
    const ctx: *EnumerationContext = @alignCast(@ptrCast(user.?));
    ctx.dev = ctx.dev.parent.?;
    return .@"continue";
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
