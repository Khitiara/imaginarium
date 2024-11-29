const uacpi = @import("uacpi.zig");
const std = @import("std");
const log = std.log.scoped(.uacpi);

const hal = @import("../../hal.zig");
const arch = hal.arch;
const vmm = arch.vmm;
const pmm = arch.pmm;
const serial = arch.serial;
const uacpi_allocator = vmm.gpa.allocator();
const ptr_from_physaddr = pmm.ptr_from_physaddr;
const physaddr_from_ptr = pmm.physaddr_from_ptr;
const PhysAddr = pmm.PhysAddr;

const SpinLock = hal.SpinLock;
const Mutex = @import("../../../thread/Mutex.zig");
const Semaphore = @import("../../../thread/Semaphore.zig");

export fn uacpi_kernel_log(level: uacpi.log_level, string: [*:0]const u8) callconv(.C) void {
    switch (level) {
        .debug => log.debug("{s}", .{string}),
        .trace => log.debug("{s}", .{string}),
        .info => log.info("{s}", .{string}),
        .warn => log.warn("{s}", .{string}),
        .err => log.err("{s}", .{string}),
    }
}

export fn uacpi_kernel_alloc(size: usize) callconv(.C) ?[*]u8 {
    const ret = uacpi_allocator.alloc(u8, size) catch return null;
    return ret.ptr;
}

fn alignedAlloc2(alloc: std.mem.Allocator, len: usize, alignment: usize) ?[*]u8 {
    return alloc.rawAlloc(len, @intCast(std.math.log2(alignment)), @returnAddress());
}

export fn uacpi_kernel_calloc(count: usize, size: usize) callconv(.C) ?[*]u8 {
    const ret = alignedAlloc2(uacpi_allocator, count * size, size) orelse return null;
    @memset(ret[0 .. count * size], 0);
    return ret;
}

export fn uacpi_kernel_free(address: [*]u8, size: usize) callconv(.C) void {
    uacpi_allocator.free(address[0..size]);
}

export fn uacpi_kernel_raw_memory_read(address: PhysAddr, byte_width: u8, ret: *u64) callconv(.C) uacpi.uacpi_status {
    ret.* = @intCast(switch (byte_width) {
        1 => ptr_from_physaddr(*const volatile u8, address).*,
        2 => ptr_from_physaddr(*const volatile u16, address).*,
        4 => ptr_from_physaddr(*const volatile u32, address).*,
        8 => ptr_from_physaddr(*const volatile u64, address).*,
        else => return .invalid_argument,
    });
    return .ok;
}

export fn uacpi_kernel_raw_memory_write(address: PhysAddr, byte_width: u8, value: u64) callconv(.C) uacpi.uacpi_status {
    switch (byte_width) {
        1 => ptr_from_physaddr(*volatile u8, address).* = @intCast(value),
        2 => ptr_from_physaddr(*volatile u16, address).* = @intCast(value),
        4 => ptr_from_physaddr(*volatile u32, address).* = @intCast(value),
        8 => ptr_from_physaddr(*volatile u64, address).* = @intCast(value),
        else => return .invalid_argument,
    }
    return .ok;
}

export fn uacpi_kernel_raw_io_read(port: uacpi.IoAddress, byte_width: u8, ret: *u64) callconv(.C) uacpi.uacpi_status {
    ret.* = @intCast(switch (byte_width) {
        1 => serial.in(@intCast(@intFromEnum(port)), u8),
        2 => serial.in(@intCast(@intFromEnum(port)), u16),
        4 => serial.in(@intCast(@intFromEnum(port)), u32),
        else => return .invalid_argument,
    });
    return .ok;
}

export fn uacpi_kernel_raw_io_write(port: uacpi.IoAddress, byte_width: u8, value: u64) callconv(.C) uacpi.uacpi_status {
    switch (byte_width) {
        1 => serial.out(@intCast(@intFromEnum(port)), @as(u8, @intCast(value))),
        2 => serial.out(@intCast(@intFromEnum(port)), @as(u16, @intCast(value))),
        4 => serial.out(@intCast(@intFromEnum(port)), @as(u32, @intCast(value))),
        else => return .invalid_argument,
    }
    return .ok;
}

export fn uacpi_kernel_map(address: PhysAddr, length: usize) callconv(.C) *anyopaque {
    _ = length;
    return ptr_from_physaddr(*anyopaque, address);
}

export fn uacpi_kernel_unmap(address: *anyopaque) callconv(.C) void {
    _ = address;
}

export fn uacpi_kernel_get_rsdp(addr: *PhysAddr) uacpi.uacpi_status {
    addr.* = @import("../acpi.zig").find_rsdp() catch |e| return .status(e);
    return .ok;
}

export fn uacpi_kernel_pci_read(address: *uacpi.PciAddress, offset: usize, byte_width: u8, ret: *u64) callconv(.C) uacpi.uacpi_status {
    _ = address;
    _ = offset;
    _ = byte_width;
    _ = ret;
    return .unimplemented;
}

export fn uacpi_kernel_pci_write(address: *uacpi.PciAddress, offset: usize, byte_width: u8, value: u64) callconv(.C) uacpi.uacpi_status {
    _ = address;
    _ = offset;
    _ = byte_width;
    _ = value;
    return .unimplemented;
}

pub const IoMap = extern struct {
    port: u16,
    length: usize,
};

export fn uacpi_kernel_io_map(port: uacpi.IoAddress, length: usize, ret: **IoMap) callconv(.C) uacpi.uacpi_status {
    ret.* = uacpi_allocator.create(IoMap) catch undefined;
    ret.*.port = @intCast(@intFromEnum(port));
    ret.*.length = length;
    return .ok;
}

export fn uacpi_kernel_io_unmap(ret: *IoMap) callconv(.C) uacpi.uacpi_status {
    uacpi_allocator.destroy(ret);
    return .ok;
}

export fn uacpi_kernel_io_read(handle: *IoMap, offset: usize, byte_width: u8, ret: *u64) callconv(.C) uacpi.uacpi_status {
    if (offset >= handle.length) return .invalid_argument;
    return uacpi_kernel_raw_io_read(@enumFromInt(handle.port + offset), byte_width, ret);
}

export fn uacpi_kernel_io_write(handle: *IoMap, offset: usize, byte_width: u8, value: u64) callconv(.C) uacpi.uacpi_status {
    if (offset >= handle.length) return .invalid_argument;
    return uacpi_kernel_raw_io_write(@enumFromInt(handle.port + offset), byte_width, value);
}

export fn uacpi_kernel_get_thread_id() u64 {
    if (@import("../../../smp.zig").lcb.*.current_thread) |t| {
        return t.client_ids.threadid;
    } else {
        // the initial thread of the BSP will always be thread id 0
        // the invalid thread id is always -1
        // the idle thread will always be thread id -2
        // all other thread ids are randomly generated
        return 0;
    }
}

export fn uacpi_kernel_get_nanoseconds_since_boot() callconv(.C) u64 {
    return 0;
}

export fn uacpi_kernel_stall(usec: u8) callconv(.C) void {
    _ = usec;
}

export fn uacpi_kernel_sleep(msec: u64) callconv(.C) void {
    _ = msec;
}

export fn uacpi_kernel_create_mutex() callconv(.C) ?*Mutex {
    return uacpi_allocator.create(Mutex) catch null;
}

export fn uacpi_kernel_free_mutex(ptr: *Mutex) callconv(.C) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_acquire_mutex(_: *Mutex, _: u16) callconv(.C) bool {
    return true;
}

export fn uacpi_kernel_release_mutex(_: *Mutex) callconv(.C) void {}

export fn uacpi_kernel_create_event() callconv(.C) ?*Semaphore {
    return uacpi_allocator.create(Semaphore) catch null;
}
export fn uacpi_kernel_free_event(ptr: *Semaphore) callconv(.C) void {
    uacpi_allocator.destroy(ptr);
}
export fn uacpi_kernel_wait_for_event(_: *Semaphore, _: u16) callconv(.C) bool {
    return true;
}
export fn uacpi_kernel_signal_event(_: *Semaphore) callconv(.C) void {}
export fn uacpi_kernel_reset_event(_: *Semaphore) callconv(.C) void {}

export fn uacpi_kernel_handle_firmware_request(_: [*c]uacpi.FirmwareRequestRaw) callconv(.C) uacpi.uacpi_status {
    return .unimplemented;
}
export fn uacpi_kernel_install_interrupt_handler(irq: u32, _: uacpi.InterruptHandler, ctx: ?*anyopaque, out_irq_handle: *?*anyopaque) callconv(.C) uacpi.uacpi_status {
    _ = irq;
    _ = ctx;
    _ = out_irq_handle;
    return .unimplemented;
}
export fn uacpi_kernel_uninstall_interrupt_handler(_: uacpi.InterruptHandler, irq_handle: ?*anyopaque) callconv(.C) uacpi.uacpi_status {
    _ = irq_handle;
    return .unimplemented;
}
export fn uacpi_kernel_create_spinlock() callconv(.C) ?*SpinLock {
    return uacpi_allocator.create(SpinLock) catch null;
}

export fn uacpi_kernel_free_spinlock(ptr: *SpinLock) callconv(.C) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_lock_spinlock(lock: *SpinLock) callconv(.C) arch.Flags {
    return lock.lock();
}

export fn uacpi_kernel_unlock_spinlock(lock: *SpinLock, state: arch.Flags) callconv(.C) void {
    lock.unlock(state);
}

export fn uacpi_kernel_schedule_work(_: uacpi.WorkType, _: uacpi.WorkHandler, _: ?*anyopaque) uacpi.uacpi_status {
    return .unimplemented;
}

export fn uacpi_kernel_wait_for_work_completion() uacpi.uacpi_status {
    return .unimplemented;
}
