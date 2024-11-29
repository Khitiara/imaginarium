pub const acpi = @import("acpi/acpi.zig");
pub const arch = @import("arch/arch.zig");
pub const apic = @import("apic/apic.zig");
pub const memory = @import("memory.zig");
pub const SpinLock = @import("SpinLock.zig");

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