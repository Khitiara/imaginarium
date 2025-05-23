const uacpi = @import("zuacpi").uacpi;
const std = @import("std");
const cmn = @import("cmn");
const types = cmn.types;

const pci = @import("../pci/pci.zig");
const mcfg = @import("mcfg.zig");

const log = std.log.scoped(.uacpi);

const hal = @import("../hal.zig");
const apic = hal.apic;
const ioapic = apic.ioapic;
const arch = hal.arch;
const serial = arch.serial;
const uacpi_allocator = hal.mm.pool.pool_allocator;
const PhysAddr = types.PhysAddr;

const dispatcher = @import("../../dispatcher/dispatcher.zig");

const interrupts = @import("../../io/interrupts.zig");

const SpinLock = hal.SpinLock;
const Mutex = @import("../../thread/Mutex.zig");
const Semaphore = @import("../../thread/Semaphore.zig");

export fn uacpi_kernel_map(address: PhysAddr, length: usize) callconv(arch.cc) ?*anyopaque {
    return (hal.mm.map_io(address, length, .write_back) catch |e| {
        log.err("error in io mapping: {}", .{e});
        if(@errorReturnTrace()) |trc| {
            @import("../../debug.zig").print_stack_trace( null, trc) catch {};
        }
        return null;
    }).ptr;
}

export fn uacpi_kernel_unmap(address: [*]u8, length: usize) callconv(arch.cc) void {
    hal.mm.unmap_io(address[0..length]);
}

export fn uacpi_kernel_get_rsdp(addr: *PhysAddr) callconv(arch.cc) uacpi.uacpi_status {
    addr.* = @import("../../boot/boot_info.zig").rsdp_addr;
    return .ok;
}

export fn uacpi_kernel_pci_device_open(address: uacpi.PciAddress, out_handle: **pci.PciBridgeAddress) callconv(arch.cc) uacpi.uacpi_status {
    const bridge = for (mcfg.host_bridges) |*b| {
        if (b.segment_group == address.segment)
            break b;
    } else null;
    out_handle.* = uacpi_allocator.create(pci.PciBridgeAddress) catch return .out_of_memory;
    out_handle.*.* = .{
        .bridge = bridge,
        .segment = address.segment,
        .bus = @intCast(address.bus),
        .device = @intCast(address.device),
        .function = @intCast(address.function),
    };
    return .ok;
}

export fn uacpi_kernel_pci_device_close(addr: *pci.PciBridgeAddress) void {
    uacpi_allocator.destroy(addr);
}

export fn uacpi_kernel_io_map(port: uacpi.IoAddress, _: usize, ret: *u16) callconv(arch.cc) uacpi.uacpi_status {
    ret.* = @intCast(@intFromEnum(port));
    return .ok;
}

export fn uacpi_kernel_io_unmap(_: *u16) callconv(arch.cc) uacpi.uacpi_status {
    return .ok;
}

comptime {
    for (&.{ u8, u16, u32 }) |T| {
        const S = struct {
            pub fn ir(handle: u16, offset: usize, ret: *T) callconv(arch.cc) uacpi.uacpi_status {
                @setRuntimeSafety(false);

                ret.* = arch.serial.in(@intCast(handle + offset), T);
                return .ok;
            }
            pub fn iw(handle: u16, offset: usize, value: T) callconv(arch.cc) uacpi.uacpi_status {
                @setRuntimeSafety(false);

                arch.serial.out(@intCast(handle + offset), value);
                return .ok;
            }
            pub fn pr(address: *pci.PciBridgeAddress, offset: usize, ret: *T) callconv(arch.cc) uacpi.uacpi_status {
                @setRuntimeSafety(false);

                ret.* = pci.config_read_with_bridge(address.*, offset, T) catch |err| switch (err) {
                    inline else => |e| return comptime uacpi.uacpi_status.status(e),
                };
                return .ok;
            }
            pub fn pw(address: *pci.PciBridgeAddress, offset: usize, value: T) callconv(arch.cc) uacpi.uacpi_status {
                @setRuntimeSafety(false);

                pci.config_write_with_bridge(address.*, offset, value) catch |err| switch (err) {
                    inline else => |e| return comptime uacpi.uacpi_status.status(e),
                };
                return .ok;
            }
        };

        @export(&S.ir, .{ .name = std.fmt.comptimePrint("uacpi_kernel_io_read{d}", .{@bitSizeOf(T)}) });
        @export(&S.iw, .{ .name = std.fmt.comptimePrint("uacpi_kernel_io_write{d}", .{@bitSizeOf(T)}) });
        @export(&S.pr, .{ .name = std.fmt.comptimePrint("uacpi_kernel_pci_read{d}", .{@bitSizeOf(T)}) });
        @export(&S.pw, .{ .name = std.fmt.comptimePrint("uacpi_kernel_pci_write{d}", .{@bitSizeOf(T)}) });
    }
}

const smp = @import("../../smp.zig");
const Thread = @import("../../thread/Thread.zig");

export fn uacpi_kernel_get_thread_id() callconv(arch.cc) ?*Thread {
    return smp.lcb.*.current_thread;
}

export fn uacpi_kernel_get_nanoseconds_since_boot() callconv(arch.cc) u64 {
    return @truncate(@as(u128, @intCast(arch.time.ns_since_boot_tsc() catch 0)));
}

export fn uacpi_kernel_stall(usec: u8) callconv(arch.cc) void {
    _ = usec;
}

export fn uacpi_kernel_sleep(msec: u64) callconv(arch.cc) void {
    _ = msec;
}

export fn uacpi_kernel_create_mutex() callconv(arch.cc) ?*Mutex {
    const m = uacpi_allocator.create(Mutex) catch return null;
    m.* = .{};
    return m;
}

export fn uacpi_kernel_free_mutex(ptr: *Mutex) callconv(arch.cc) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_acquire_mutex(mutex: *Mutex, timeout: u16) callconv(arch.cc) uacpi.uacpi_status {
    if (timeout != 0) {
        dispatcher.wait_for_single_object(&mutex.wait_handle) catch return .internal_error;
        return .ok;
    } else {
        return if (mutex.tryLock()) .ok else .timeout;
    }
}

export fn uacpi_kernel_release_mutex(mutex: *Mutex) callconv(arch.cc) void {
    mutex.release();
}

export fn uacpi_kernel_create_event() callconv(arch.cc) ?*Semaphore {
    const s = uacpi_allocator.create(Semaphore) catch return null;
    s.* = .{ .permits = 0 };
    return s;
}

export fn uacpi_kernel_free_event(ptr: *Semaphore) callconv(arch.cc) void {
    uacpi_allocator.destroy(ptr);
}

export fn uacpi_kernel_wait_for_event(sema: *Semaphore, timeout: u16) callconv(arch.cc) bool {
    if (timeout != 0) {
        dispatcher.wait_for_single_object(&sema.wait_handle) catch unreachable;
        return true;
    } else {
        return sema.try_wait();
    }
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
    gsi: u32,
};

fn do_handle(_: *interrupts.InterruptRegistration, context: ?*anyopaque) bool {
    const ctx: *IrqContext = @alignCast(@ptrCast(context orelse return false));
    return switch (ctx.handler(ctx.ctx)) {
        .handled => true,
        .not_handled => false,
    };
}

noinline fn find_redirect_suitable_vector(gsi: u32) !u8 {
    if (gsi < 32) {
        const isa_irq = &ioapic.isa_irqs[gsi];
        if (isa_irq.cpu_irq == 0) {
            const vector = arch.idt.allocate_vector_any(.dispatch) catch return error.InternalError;
            const redir: ioapic.IoRedTblEntry = .{
                .vector = vector,
                .delivery_mode = .fixed,
                .dest_mode = .physical,
                .polarity = isa_irq.polarity,
                .trigger_mode = isa_irq.trigger,
                .destination = apic.get_lapic_id(),
            };
            ioapic.redirect_irq(gsi, redir) catch |err| switch (err) {
                error.NoSuitableIoApic => return error.InternalError,
                error.AlreadyMappedIsaIrq => return error.AlreadyExists,
                inline else => |e| return e,
            };
            isa_irq.cpu_irq = @bitCast(vector);
        }
        return isa_irq.cpu_irq;
    } else @panic("unimplemented");
}

export fn uacpi_kernel_install_interrupt_handler(gsi: u32, handler: uacpi.InterruptHandler, ctx: ?*anyopaque, out_irq_handle: **interrupts.InterruptRegistration) callconv(arch.cc) uacpi.uacpi_status {
    const cpu_irq = find_redirect_suitable_vector(gsi) catch |e| switch (e) {
        inline else => |e2| return uacpi.uacpi_status.status(e2),
    };
    log.debug("uacpi requested installation of shareable interrupt handler for gsi vector 0x{x}. redirected to vector 0x{x:0<2} on current core", .{ gsi, cpu_irq });
    const c = uacpi_allocator.create(IrqContext) catch return .out_of_memory;
    c.ctx = ctx;
    c.handler = handler;
    c.gsi = gsi;
    out_irq_handle.* = interrupts.InterruptRegistration.connect(.{
        .vector = @bitCast(@as(u8, @intCast(cpu_irq))),
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

export fn uacpi_kernel_lock_spinlock(lock: *SpinLock) callconv(arch.cc) u8 {
    return @intFromEnum(lock.lock());
}

export fn uacpi_kernel_unlock_spinlock(lock: *SpinLock, state: u8) callconv(arch.cc) void {
    lock.unlock(@enumFromInt(@as(u4, @truncate(state))));
}

export fn uacpi_kernel_schedule_work(_: uacpi.WorkType, _: uacpi.WorkHandler, _: ?*anyopaque) callconv(arch.cc) uacpi.uacpi_status {
    return .unimplemented;
}

export fn uacpi_kernel_wait_for_work_completion() callconv(arch.cc) uacpi.uacpi_status {
    return .unimplemented;
}
