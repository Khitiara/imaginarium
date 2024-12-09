const std = @import("std");
const Device = @import("Device.zig");
const queue = @import("util").queue;

const Irp = @This();

pub const InvocationResult = enum {
    complete,
    pending,
    pass,
};

pub const Function = enum {
    enumeration,
};

pub const Parameters = union(Function) {
    enumeration: union(enum) {
        properties: union(enum) {
            hardware_ids: ?[]const []const u8,
            compatible_ids: ?[]const []const u8,
            pci_class: struct {
                class: u8,
                subclass: u8,
                prog_if: u8,
            },
            address: u64,
        },
        bus_children: ?[]const *Device,
    },
};

alloc: std.mem.Allocator,
device: *Device,
stack_position: ?*Device.DriverStackEntry,
queue_hook: queue.Node = .{},
parameters: Parameters,
completion: ?struct {
    routine: *const fn(*Irp, ?*anyopaque) anyerror!void,
    ctx: ?*anyopaque,
} = null,

pub fn init(alloc: std.mem.Allocator, device: *Device, parameters: Parameters) !*Irp {
    const irp = try alloc.create(Irp);
    irp.* = .{
        .alloc = alloc,
        .device = device,
        .parameters = parameters,
    };
    return irp;
}

pub fn deinit(self: *Irp) void {
    switch (self.parameters) {
        .enumeration => |e| {
            switch (e) {
                .properties => |p| {
                    switch (p) {
                        .compatible_ids => |cids_opt| if (cids_opt) |cids| {
                            for (cids) |c| {
                                self.alloc.free(c);
                            }
                            self.alloc.free(cids);
                        },
                        .hardware_ids => |cids_opt| if (cids_opt) |cids| {
                            for (cids) |c| {
                                self.alloc.free(c);
                            }
                            self.alloc.free(cids);
                        },
                        .pci_class, .address => {},
                    }
                },
                .bus_children => |b| if(b) |kids| {
                    self.alloc.free(kids);
                }
            }
        },
    }
    self.alloc.destroy(self);
}
