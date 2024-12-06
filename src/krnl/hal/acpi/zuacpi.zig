const uacpi = @import("uacpi/uacpi.zig");
const acpi = @import("acpi.zig");
const sdt = acpi.sdt;
const madt = acpi.madt;
const mcfg = acpi.mcfg;
const hpet = acpi.hpet;

const arch = @import("../arch/arch.zig");
const std = @import("std");
const log = std.log.scoped(.acpi);

comptime {
    _ = @import("uacpi/uacpi_libc.zig");
    _ = @import("uacpi/shims.zig");
}

pub fn init() !void {
    try uacpi.initialize(.{});
    log.info("uacpi initialized", .{});
    try find_load_table(.APIC);
    log.debug("madt initialized", .{});
    try find_load_table(.MCFG);
    log.debug("mcfg initialized", .{});
    try find_load_table(.HPET);
    log.debug("hpet initialized", .{});
}

pub fn load_namespace() !void {
    const fadt = try uacpi.tables.table_fadt();
    const isa_irq = ioapic.isa_irqs[fadt.sci_int];
    try ioapic.redirect_irq(fadt.sci_int, .{
        .vector = @bitCast(@as(u8, 0x20)),
        .delivery_mode = .fixed,
        .dest_mode = .physical,
        .polarity = isa_irq.polarity,
        .trigger_mode = isa_irq.trigger,
        .destination = 0,
    });

    try uacpi.namespace_load();
    try uacpi.utilities.set_interrupt_model(.ioapic);
    log.info("ACPI namespace parsed", .{});
}

const ioapic = @import("../apic/ioapic.zig");

pub fn initialize_namespace() !void {
    try uacpi.namespace_initialize();
    log.info("ACPI namespace initialized", .{});
}

fn find_load_table(sig: sdt.Signature) !void {
    var tbl = (try uacpi.tables.find_table_by_signature(sig)) orelse return;
    try acpi.load_table(tbl.location.hdr);
    try uacpi.tables.table_unref(&tbl);
}

const namespace = uacpi.namespace;

fn obj_cb_asc(_: ?*anyopaque, node: *namespace.NamespaceNode, depth: u32) callconv(arch.cc) namespace.IterationDecision {
    const path = namespace.uacpi_namespace_node_generate_absolute_path(node) orelse return .@"continue";
    defer namespace.uacpi_free_absolute_path(path);
    log.debug("ACPI Enumerated object {s}, depth {d}, of type {s}", .{ path, depth, @tagName(namespace.node_type(node) catch .uninitialized) });
    return .@"continue";
}
fn obj_cb_desc(_: ?*anyopaque, node: *namespace.NamespaceNode, depth: u32) callconv(arch.cc) namespace.IterationDecision {
    const path = namespace.uacpi_namespace_node_generate_absolute_path(node) orelse return .@"continue";
    defer namespace.uacpi_free_absolute_path(path);
    log.debug("ACPI left object {s}, depth {d}, of type {s}", .{ path, depth, @tagName(namespace.node_type(node) catch .uninitialized) });
    return .@"continue";
}

pub fn enumerate_stuff() !void {
    try namespace.for_each_child(namespace.uacpi_namespace_root(), &obj_cb_asc, &obj_cb_desc, .{ .device = true, .processor = true, .thermal_zone = true }, std.math.maxInt(u32), undefined);
}
