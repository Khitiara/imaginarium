const uacpi = @import("zuacpi").uacpi;
const cmn = @import("cmn");
const types = cmn.types;
const PhysAddr = types.PhysAddr;

const boot = @import("boot/boot_info.zig");

export fn uacpi_kernel_map(address: PhysAddr, length: usize) callconv(arch.cc) ?*anyopaque {
    return boot.hhdm_base()[@intFromEnum(address)..][0..length];
}

export fn uacpi_kernel_unmap(_: [*]u8, _: usize) callconv(arch.cc) void {}

export fn uacpi_kernel_get_rsdp(addr: *PhysAddr) callconv(arch.cc) uacpi.uacpi_status {
    addr.* = @import("../../boot/boot_info.zig").rsdp_addr;
    return .ok;
}
