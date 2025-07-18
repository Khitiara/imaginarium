pub const cpuid = @import("cpuid.zig");
pub const msr = @import("msr.zig");
pub const segmentation = @import("segmentation.zig");
pub const control_registers = @import("ctrl_registers.zig");
pub const serial = @import("serial.zig");
pub const descriptors = @import("descriptors.zig");
pub const gdt = @import("gdt.zig");
pub const idt = @import("idt.zig");
pub const interrupts = @import("interrupts.zig");
pub const rand = @import("rand.zig");
pub const smp = @import("smp.zig");
pub const time = @import("time.zig");
pub const init = @import("init.zig");

const std = @import("std");
const cmn = @import("cmn");
const types = cmn.types;
const hal = @import("../hal.zig");

const acpi = @import("../acpi/acpi.zig");
const apic = @import("../apic/apic.zig");

pub const cc: @import("std").builtin.CallingConvention = types.cc;

pub inline fn puts(bytes: []const u8) void {
    for (bytes) |b| {
        serial.out(0xE9, b);
    }
}

pub const SerialWriter = struct {
    const WriteError = error{};
    pub const Writer = std.io.GenericWriter(*const anyopaque, error{}, typeErasedWriteFn);

    fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) error{}!usize {
        _ = context;
        puts(bytes);
        return bytes.len;
    }

    pub fn writer() Writer {
        return .{ .context = undefined };
    }
};

pub fn delay_unsafe(cycles: u64) void {
    const target = time.rdtsc() + cycles;
    while (time.rdtsc() < target) {
        std.atomic.spinLoopHint();
    }
}

comptime {
    _ = idt;
    _ = init;
}

pub const Flags = types.Flags;

pub fn flags() Flags {
    return asm volatile (
        \\pushfq
        \\pop %[flags]
        : [flags] "=r" (-> Flags),
    );
}

pub fn setflags(f: Flags) void {
    asm volatile (
        \\push %[flags]
        \\popfq
        :
        : [flags] "r" (f),
        : "flags"
    );
}

pub const SavedRegisterState = idt.InterruptFrame(u64);

pub const acpi_types = struct {
    pub const MsiAddressRegister = packed struct(u32) {
        _1: u2 = 0,
        dm: enum(u1) {
            physical = 0,
            logical = 1,
        },
        rh: enum(u1) {
            direct = 0,
            indirect = 1,
        },
        _2: u8 = 0,
        destination_id: u8,
        _3: u12 = 0xFEE,
    };
    pub const MsiDataRegister = packed struct(u64) {
        vector: u8,
        delivery_mode: apic.DeliveryMode,
        _1: u3 = 0,
        assert: bool,
        trigger_mode: apic.TriggerMode,
        _2: u48 = 0,
    };
};

test {
    @import("std").testing.refAllDecls(@This());
}
