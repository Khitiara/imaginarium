const uacpi = @import("uacpi.zig");
const std = @import("std");
const cmn = @import("cmn");
const types = cmn.types;

const pci = @import("../../pci/pci.zig");
const mcfg = @import("../mcfg.zig");

const log = std.log.scoped(.uacpi);

const hal = @import("../../hal.zig");
const arch = hal.arch;
const vmm = arch.vmm;
const pmm = arch.pmm;
const serial = arch.serial;
const uacpi_allocator = vmm.gpa.allocator();
const ptr_from_physaddr = pmm.ptr_from_physaddr;
const physaddr_from_ptr = pmm.physaddr_from_ptr;
const PhysAddr = types.PhysAddr;

const interrupts = @import("../../../io/interrupts.zig");

const SpinLock = hal.SpinLock;
const Mutex = @import("../../../thread/Mutex.zig");
const Semaphore = @import("../../../thread/Semaphore.zig");

export fn uacpi_kernel_log(level: uacpi.log_level, string: [*:0]const u8) callconv(arch.cc) void {
    const str = std.mem.span(string);
    const s = std.mem.trim(u8, str, " \n\r\t");
    switch (level) {
        .debug, .trace => log.debug("{s}", .{s}),
        .info => log.info("{s}", .{s}),
        .warn => log.warn("{s}", .{s}),
        .err => log.err("{s}", .{s}),
    }
}

export fn uacpi_kernel_alloc(size: usize) callconv(arch.cc) ?[*]u8 {
    const ret = uacpi_allocator.alloc(u8, size) catch return null;
    return ret.ptr;
}

fn alignedAlloc2(alloc: std.mem.Allocator, len: usize, alignment: usize) callconv(arch.cc) ?[*]u8 {
    return alloc.rawAlloc(len, @intCast(std.math.log2(alignment)), @returnAddress());
}

export fn uacpi_kernel_calloc(count: usize, size: usize) callconv(arch.cc) ?[*]u8 {
    const ret = uacpi_allocator.alloc(u8, count * size) catch return null;
    @memset(ret, 0);
    return ret.ptr;
}

export fn uacpi_kernel_free(address: [*]u8, size: usize) callconv(arch.cc) void {
    uacpi_allocator.free(address[0..size]);
}

export fn uacpi_kernel_raw_memory_read(address: PhysAddr, byte_width: u8, ret: *u64) callconv(arch.cc) uacpi.uacpi_status {
    ret.* = @intCast(switch (byte_width) {
        1 => ptr_from_physaddr(*const volatile u8, address).*,
        2 => ptr_from_physaddr(*const volatile u16, address).*,
        4 => ptr_from_physaddr(*const volatile u32, address).*,
        8 => ptr_from_physaddr(*const volatile u64, address).*,
        else => return .invalid_argument,
    });
    return .ok;
}

export fn uacpi_kernel_raw_memory_write(address: PhysAddr, byte_width: u8, value: u64) callconv(arch.cc) uacpi.uacpi_status {
    switch (byte_width) {
        1 => ptr_from_physaddr(*volatile u8, address).* = @intCast(value),
        2 => ptr_from_physaddr(*volatile u16, address).* = @intCast(value),
        4 => ptr_from_physaddr(*volatile u32, address).* = @intCast(value),
        8 => ptr_from_physaddr(*volatile u64, address).* = @intCast(value),
        else => return .invalid_argument,
    }
    return .ok;
}

export fn uacpi_kernel_raw_io_read(port: uacpi.IoAddress, byte_width: u8, ret: *u64) callconv(arch.cc) uacpi.uacpi_status {
    ret.* = @intCast(switch (byte_width) {
        1 => serial.in(@intCast(@intFromEnum(port)), u8),
        2 => serial.in(@intCast(@intFromEnum(port)), u16),
        4 => serial.in(@intCast(@intFromEnum(port)), u32),
        else => return .invalid_argument,
    });
    return .ok;
}

export fn uacpi_kernel_raw_io_write(port: uacpi.IoAddress, byte_width: u8, value: u64) callconv(arch.cc) uacpi.uacpi_status {
    switch (byte_width) {
        1 => serial.out(@intCast(@intFromEnum(port)), @as(u8, @intCast(value))),
        2 => serial.out(@intCast(@intFromEnum(port)), @as(u16, @intCast(value))),
        4 => serial.out(@intCast(@intFromEnum(port)), @as(u32, @intCast(value))),
        else => return .invalid_argument,
    }
    return .ok;
}

export fn uacpi_kernel_map(address: PhysAddr, length: usize) callconv(arch.cc) *anyopaque {
    _ = length;
    return ptr_from_physaddr(*anyopaque, address);
}

export fn uacpi_kernel_unmap(address: *anyopaque) callconv(arch.cc) void {
    _ = address;
}

export fn uacpi_kernel_get_rsdp(addr: *PhysAddr) callconv(arch.cc) uacpi.uacpi_status {
    addr.* = @import("../acpi.zig").find_rsdp() catch |e| return .status(e);
    return .ok;
}

export fn uacpi_kernel_pci_read(address: *uacpi.PciAddress, offset: usize, byte_width: u8, ret: *u64) callconv(arch.cc) uacpi.uacpi_status {
    switch (byte_width) {
        inline 1, 2, 4 => |bw| {
            const T = switch (bw) {
                1 => u8,
                2 => u16,
                4 => u32,
                else => unreachable,
            };
            ret.* = pci.config_read(.{
                .segment = address.segment,
                .bus = @intCast(address.bus),
                .device = @intCast(address.device),
                .function = @intCast(address.function),
                .offset = offset,
            }, T) catch |err| switch (err) {
                inline else => |e| return comptime uacpi.uacpi_status.status(e),
            };
            return .ok;
        },
        else => return .invalid_argument,
    }
}

export fn uacpi_kernel_pci_write(address: *uacpi.PciAddress, offset: usize, byte_width: u8, value: u64) callconv(arch.cc) uacpi.uacpi_status {
    switch (byte_width) {
        inline 1, 2, 4 => |bw| {
            const T = switch (bw) {
                1 => u8,
                2 => u16,
                4 => u32,
                else => unreachable,
            };
            pci.config_write(.{
                .segment = address.segment,
                .bus = @intCast(address.bus),
                .device = @intCast(address.device),
                .function = @intCast(address.function),
                .offset = offset,
            }, @as(T, @intCast(value))) catch |err| switch (err) {
                inline else => |e| return comptime uacpi.uacpi_status.status(e),
            };
            return .ok;
        },
        else => return .invalid_argument,
    }
}

pub const IoMap = extern struct {
    port: u16,
    length: usize,
};

export fn uacpi_kernel_io_map(port: uacpi.IoAddress, length: usize, ret: **IoMap) callconv(arch.cc) uacpi.uacpi_status {
    ret.* = uacpi_allocator.create(IoMap) catch return .out_of_memory;
    ret.*.port = @intCast(@intFromEnum(port));
    ret.*.length = length;
    return .ok;
}

export fn uacpi_kernel_io_unmap(ret: *IoMap) callconv(arch.cc) uacpi.uacpi_status {
    uacpi_allocator.destroy(ret);
    return .ok;
}

export fn uacpi_kernel_io_read(handle: *IoMap, offset: usize, byte_width: u8, ret: *u64) callconv(arch.cc) uacpi.uacpi_status {
    if (offset >= handle.length) return .invalid_argument;
    return uacpi_kernel_raw_io_read(@enumFromInt(handle.port + offset), byte_width, ret);
}

export fn uacpi_kernel_io_write(handle: *IoMap, offset: usize, byte_width: u8, value: u64) callconv(arch.cc) uacpi.uacpi_status {
    if (offset >= handle.length) return .invalid_argument;
    return uacpi_kernel_raw_io_write(@enumFromInt(handle.port + offset), byte_width, value);
}

export fn uacpi_kernel_get_thread_id() callconv(arch.cc) u64 {
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

export fn uacpi_kernel_get_nanoseconds_since_boot() callconv(arch.cc) u64 {
    return 0;
}

export fn uacpi_kernel_stall(usec: u8) callconv(arch.cc) void {
    _ = usec;
}

export fn uacpi_kernel_sleep(msec: u64) callconv(arch.cc) void {
    _ = msec;
}

export fn uacpi_kernel_create_mutex() callconv(arch.cc) ?*Mutex {
    return uacpi_allocator.create(Mutex) catch null;
}

export fn uacpi_kernel_free_mutex(ptr: *Mutex) callconv(arch.cc) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_acquire_mutex(_: *Mutex, _: u16) callconv(arch.cc) uacpi.uacpi_status {
    return .ok;
}

export fn uacpi_kernel_release_mutex(_: *Mutex) callconv(arch.cc) void {}

export fn uacpi_kernel_create_event() callconv(arch.cc) ?*Semaphore {
    return uacpi_allocator.create(Semaphore) catch null;
}

export fn uacpi_kernel_free_event(ptr: *Semaphore) callconv(arch.cc) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_wait_for_event(_: *Semaphore, _: u16) callconv(arch.cc) bool {
    return true;
}

export fn uacpi_kernel_signal_event(sema: *Semaphore) callconv(arch.cc) void {
    sema.signal();
}

export fn uacpi_kernel_reset_event(sema: *Semaphore) callconv(arch.cc) void {
    sema.reset();
}

export fn uacpi_kernel_handle_firmware_request(_: [*c]uacpi.FirmwareRequestRaw) callconv(arch.cc) uacpi.uacpi_status {
    return .unimplemented;
}

const IrqContext = struct {
    handler: uacpi.InterruptHandler,
    ctx: ?*anyopaque,
};

fn do_handle(_: *interrupts.InterruptRegistration, context: ?*anyopaque) bool {
    const ctx: *IrqContext = @alignCast(@ptrCast(context orelse return false));
    return switch (ctx.handler(ctx.ctx)) {
        .handled => true,
        .not_handled => false,
    };
}

export fn uacpi_kernel_install_interrupt_handler(irq: u32, handler: uacpi.InterruptHandler, ctx: ?*anyopaque, out_irq_handle: **interrupts.InterruptRegistration) callconv(arch.cc) uacpi.uacpi_status {
    log.debug("uacpi requested installation of shareable interrupt handler for vector {x:0>2}", .{irq});
    const c = uacpi_allocator.create(IrqContext) catch return .out_of_memory;
    c.ctx = ctx;
    c.handler = handler;
    out_irq_handle.* = interrupts.InterruptRegistration.connect(.{
        .vector = @bitCast(@as(u8, @intCast(irq))),
        .context = c,
        .routine = .{ .isr = &do_handle },
    }) catch return .out_of_memory;
    return .ok;
}

export fn uacpi_kernel_uninstall_interrupt_handler(_: uacpi.InterruptHandler, irq_handle: *interrupts.InterruptRegistration) callconv(arch.cc) uacpi.uacpi_status {
    if (irq_handle.context) |c| uacpi_allocator.destroy(@as(*IrqContext, @alignCast(@ptrCast(c))));
    irq_handle.deinit();
    return .ok;
}

export fn uacpi_kernel_create_spinlock() callconv(arch.cc) ?*SpinLock {
    return uacpi_allocator.create(SpinLock) catch null;
}

export fn uacpi_kernel_free_spinlock(ptr: *SpinLock) callconv(arch.cc) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_lock_spinlock(lock: *SpinLock) callconv(arch.cc) u64 {
    return @intFromEnum(lock.lock());
}

export fn uacpi_kernel_unlock_spinlock(lock: *SpinLock, state: u64) callconv(arch.cc) void {
    lock.unlock(@enumFromInt(@as(u4, @truncate(state))));
}

export fn uacpi_kernel_schedule_work(_: uacpi.WorkType, _: uacpi.WorkHandler, _: ?*anyopaque) callconv(arch.cc) uacpi.uacpi_status {
    return .unimplemented;
}

export fn uacpi_kernel_wait_for_work_completion() callconv(arch.cc) uacpi.uacpi_status {
    return .unimplemented;
}
