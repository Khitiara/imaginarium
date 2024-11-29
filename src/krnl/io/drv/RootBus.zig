const Driver = @import("../Driver.zig");
const Device = @import("../Device.zig");
const ob = @import("../../objects/ob.zig");
const std = @import("std");

drv: Driver,

const vtable: Driver.VTable = .{
    .init = &init,
    .deinit = &ob.DeinitImpl(Driver, @This(), "drv").deinit_inner,
};

fn init(self: *Driver, alloc: std.mem.Allocator) Driver.InitError!void {
    self.init_internal();
    // const this: *@This() = @fieldParentPtr("drv", self);
    const rootbus = try alloc.create(Device);
    rootbus.init(self, null, "ROOT");

    const pci0 = try alloc.create(Device);
    pci0.init(self, rootbus, "PCI0");
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}
