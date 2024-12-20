pub const acpi = @import("acpi/acpi.zig");
pub const arch = @import("arch/arch.zig");
pub const apic = @import("apic/apic.zig");
pub const SpinLock = @import("SpinLock.zig");
pub const QueuedSpinLock = @import("QueuedSpinLock.zig");

pub const InterruptRequestPriority = enum(u4) {
    passive = 0x0,
    dispatch = 0x2,
    dpc = 0x3,
    dev_0 = 0x4,
    dev_1 = 0x5,
    dev_2 = 0x6,
    dev_3 = 0x7,
    dev_4 = 0x8,
    dev_5 = 0x9,
    dev_6 = 0xA,
    dev_7 = 0xB,
    sync = 0xC,
    clock = 0xD,
    ipi = 0xE,
    high = 0xF,
    /// exclude IRQL 1 because we cant make actual vectors with that priority
    _,

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

pub inline fn fetch_set_irql(level: InterruptRequestPriority, op: IrqlOp) InterruptRequestPriority {
    const restore = arch.idt.get_and_disable();
    defer arch.idt.restore(restore);
    const l = @import("../smp.zig").lcb.*;
    defer {
        if (switch (op) {
            .any => true,
            .raise => @intFromEnum(level) > @intFromEnum(l.irql),
            .lower => @intFromEnum(level) < @intFromEnum(l.irql),
        }) {
            l.irql = level;
            arch.control_registers.write(.cr8, .{ .tpr = @intFromEnum(level) });
        }
    }
    return l.irql;
}

pub inline fn set_irql(level: InterruptRequestPriority, op: IrqlOp) InterruptRequestPriority {
    _ = fetch_set_irql(level, op);
    return level;
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