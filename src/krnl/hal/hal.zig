const std = @import("std");

pub const acpi = @import("acpi/acpi.zig");
pub const arch = switch (@import("builtin").cpu.arch) {
    .x86_64 => @import("arch/x86_64/arch.zig"),
    .aarch64 => @import("arch/aarch64/arch.zig"),
    else => unreachable,
};
pub const pci = @import("pci/pci.zig");
pub const mm = @import("mm/mm.zig");
pub const SpinLock = @import("spin_lock.zig").SpinLock;
pub const QueuedSpinLock = @import("QueuedSpinLock.zig");

pub const InterruptRequestPriority = enum(u4) {
    passive = 0x0,
    _unused = 0x1,
    dispatch = 0x2,
    dev_0 = 0x3,
    dev_1 = 0x4,
    dev_2 = 0x5,
    dev_3 = 0x6,
    dev_4 = 0x7,
    dev_5 = 0x8,
    dev_6 = 0x9,
    dev_7 = 0xA,
    dev_8 = 0xB,
    sync = 0xC,
    clock = 0xD,
    ipi = 0xE,
    high = 0xF,

    pub fn lower(self: InterruptRequestPriority) InterruptRequestPriority {
        if (self == .passive or self == .dispatch)
            return .passive;
        return @enumFromInt(@intFromEnum(self) - 1);
    }
    pub fn raise(self: InterruptRequestPriority) InterruptRequestPriority {
        if (self == .passive)
            return .dispatch;
        return @enumFromInt(@intFromEnum(self) +| 1);
    }
};

pub const IrqlOp = enum {
    raise,
    lower,
    any,
};

pub inline fn lower_irql(irql: InterruptRequestPriority) void {
    std.debug.assert(@intFromEnum(arch.control_registers.read(.cr8).tpr) >= @intFromEnum(irql));
    arch.control_registers.write(.cr8, .{ .tpr = irql });
}

pub inline fn raise_irql(irql: InterruptRequestPriority) void {
    std.debug.assert(@intFromEnum(arch.control_registers.read(.cr8).tpr) <= @intFromEnum(irql));
    arch.control_registers.write(.cr8, .{ .tpr = irql });
}

pub inline fn get_irql() InterruptRequestPriority {
    return arch.control_registers.read(.cr8).tpr;
}

pub const InterruptVector = packed struct(u8) {
    vector: u4,
    level: InterruptRequestPriority,
};

test {
    @import("std").testing.refAllDecls(@This());
}

comptime {
    _ = @import("acpi/zuacpi.zig");
}
