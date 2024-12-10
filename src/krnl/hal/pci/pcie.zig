const std = @import("std");
const mcfg = @import("../acpi/mcfg.zig");
const SerialWriter = @import("../arch/arch.zig").SerialWriter;

const TreeNode = struct {
    bus: u8,
    device: u5,
    next: ?*const TreeNode = null,
    funcs: *const Function,

    pub fn deinit(self: *const TreeNode, alloc: std.mem.Allocator) void {
        if (self.next) |n| {
            n.deinit(alloc);
        }
        var f: ?*const Function = self.funcs;
        while (f) |func| : (f = func.next) {
            func.deinit(alloc);
        }
    }
};

const Function = struct {
    function: u3,
    device_id: u16,
    vendor_id: u16,
    class: u8,
    subclass: u8,
    revision: u8,
    prog_if: u8,
    header: enum {
        general,
        pci_pci_bridge,
        pci_cardbus_bridge,
    },
    next: ?*const Function = null,
    child: ?*const TreeNode = null,
    secondary: u8 = 0,
    subordinate: u8 = 0,

    pub fn deinit(self: *const Function, alloc: std.mem.Allocator) void {
        if (self.next) |f| {
            f.deinit(alloc);
        }
        var n: ?*const TreeNode = self.child;
        while (n) |node| : (n = node.next) {
            node.deinit(alloc);
        }
    }
};

pub fn init(gpa: std.mem.Allocator) !void {
    const host_bridge = for (mcfg.host_bridges) |*b| {
        if (b.segment_group == 0 and b.bus_start == 0) break b;
    } else return;

    const tree: *const TreeNode = (try enumerate(gpa, host_bridge, 0)) orelse {
        std.log.warn("No PCI devices found", .{});
        return;
    };
    defer tree.deinit(gpa);

    const writer = SerialWriter.writer();
    var buf: std.ArrayList(u8) = try .initCapacity(gpa, 80);
    defer buf.deinit();

    try render(gpa, tree, writer, &buf);
}

fn tee(next: bool, entry: bool) []const u8 {
    if (next) {
        return if (entry) "├─ " else "│  ";
    } else {
        return if (entry) "└─ " else "   ";
    }
}

fn render(gpa: std.mem.Allocator, node: *const TreeNode, writer: SerialWriter.Writer, buf: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    try writer.print("{s}{s}Device #{d}\n", .{ buf.items, tee(node.next != null, true), node.device });
    {
        const len = buf.items.len;
        defer buf.shrinkRetainingCapacity(len);
        try buf.appendSlice(tee(node.next != null, false));
        try render_function(gpa, node.funcs, writer, buf);
    }
    if (node.next) |n| {
        try render(gpa, n, writer, buf);
    }
}

fn render_function(gpa: std.mem.Allocator, func: *const Function, writer: SerialWriter.Writer, buf: *std.ArrayList(u8)) std.mem.Allocator.Error!void {
    try writer.print("{s}{s}Function #{d}: {s} of class {x:0>2}:{x:0>2}::{x:0>2}, revision {d} with id {x:0>4} from {x:0>4}\n", .{
        buf.items,      tee(func.next != null, true),
        func.function,  @tagName(func.header),
        func.class,     func.subclass,
        func.prog_if,   func.revision,
        func.device_id, func.vendor_id,
    });

    if (func.child) |c| {
        try writer.print("{s}{s}Bus {d}\n", .{ buf.items, tee(func.next != null, true), func.secondary });

        const len = buf.items.len;
        defer buf.shrinkRetainingCapacity(len);

        try buf.appendSlice(tee(func.next != null, false));
        try render(gpa, c, writer, buf);
    }
    if (func.next) |f| {
        try render_function(gpa, f, writer, buf);
    }
}

fn enumerate_function(gpa: std.mem.Allocator, bridge: *const mcfg.PciHostBridge, bus: u8, device: u5, function: u3, multifunction: ?*bool) std.mem.Allocator.Error!?*Function {
    const block = bridge.block(bus, device, function);
    const ids: [2]u16 = @bitCast(block[0]);
    if (ids[0] == 0xFFFF) {
        return null;
    }
    const classes: [4]u8 = @bitCast(block[2]);
    const stuff: [4]u8 = @bitCast(block[3]);
    const f = try gpa.create(Function);
    f.* = .{
        .function = function,
        .device_id = ids[1],
        .vendor_id = ids[0],
        .class = classes[3],
        .subclass = classes[2],
        .revision = classes[0],
        .prog_if = classes[1],
        .header = @enumFromInt(stuff[2] & 0x7F),
    };

    if (multifunction) |mf| {
        mf.* = stuff[2] & 0x80 != 0;
    }

    if (f.header == .pci_pci_bridge) {
        const busnums: [4]u8 = @bitCast(block[6]);
        if (busnums[0] != bus) {
            std.log.warn("unexpected bridge with wrong primary bus {d} on bus {d}", .{ busnums[0], bus });
        } else {
            f.secondary = busnums[1];
            f.subordinate = busnums[2];
            f.child = try enumerate(gpa, bridge, f.secondary);
        }
    }

    return f;
}

fn enumerate(gpa: std.mem.Allocator, bridge: *const mcfg.PciHostBridge, bus: u8) std.mem.Allocator.Error!?*TreeNode {
    var start: ?*TreeNode = null;
    var end: ?*TreeNode = null;
    for (0..32) |d| {
        var multifunction: bool = false;
        var f = try enumerate_function(gpa, bridge, bus, @intCast(d), 0, &multifunction) orelse continue;
        const n = try gpa.create(TreeNode);
        start = start orelse n;
        n.* = .{
            .bus = bus,
            .device = @intCast(d),
            .funcs = f,
        };
        if (end) |e| {
            e.next = n;
        }
        end = n;

        if (multifunction) {
            for (1..8) |fnum| {
                const f1 = try enumerate_function(gpa, bridge, bus, @intCast(d), @intCast(fnum), null) orelse continue;
                f.next = f1;
                f = f1;
            }
        }
    }
    return start;
}
