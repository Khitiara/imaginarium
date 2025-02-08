const std = @import("std");
const assert = std.debug.assert;
const cpuid = @import("../arch/cpuid.zig");
pub const x2apic = @import("x2apic.zig");
pub const ioapic = @import("ioapic.zig");

const log = std.log.scoped(.apic);

pub const DeliveryMode = enum(u3) {
    fixed = 0,
    lowest = 1,
    smi = 2,
    nmi = 4,
    init = 5,
    startup = 6,
    exint = 7,
};

pub const TimerMode = enum(u2) {
    one_shot,
    periodic,
    tsc_deadline,
    _,
};

pub const ErrorStatusRegister = packed struct(u32) {
    send_checksum: bool,
    recv_checksum: bool,
    send_accept: bool,
    recv_accept: bool,
    redirectable_ipi: bool,
    send_illegal_vector: bool,
    recvd_illegal_vector: bool,
    illegal_register_address: bool,
    _: u24,
};

pub const SpuriousInterrupt = packed struct(u32) {
    spurious_vector: u8,
    apic_software_enabled: bool,
    focus_processor_checking: bool,
    _reserved1: u2,
    suppress_eoi_broadcast: bool,
    _reserved2: u19,
};

pub const TriggerMode = enum(u1) {
    edge = 0,
    level = 1,
};

pub const DestinationMode = enum(u1) {
    physical = 0,
    logical = 1,
};

pub const Icr = packed struct(u64) {
    vector: u8,
    delivery: DeliveryMode,
    dest_mode: DestinationMode,
    pending: bool = false,
    _1: u1 = 0,
    assert: bool = true,
    trigger_mode: TriggerMode,
    _2: u2 = 0,
    shorthand: enum(u2) {
        none,
        self,
        all,
        others,
    },
    _3: u36 = 0,
    dest: u8,
};

pub const Polarity = enum(u1) {
    active_high = 0,
    active_low = 1,
};

pub const LvtLintEntry = packed struct(u32) {
    vector: u8,
    delivery: DeliveryMode,
    _1: u1 = 0,
    /// read-only
    pending: bool = false,
    polarity: Polarity = .active_high,
    remote_irr: bool = false,
    trigger_mode: TriggerMode = .edge,
    masked: bool,
    _2: u17 = 0,
};

pub const LvtTimerEntry = packed struct(u32) {
    vector: u8,
    delivery: DeliveryMode,
    _1: u1 = 0,
    /// read-only
    pending: bool = false,
    polarity: enum(u1) {
        active_high = 0,
        active_low = 1,
    } = .active_high,
    remote_irr: bool = false,
    trigger_mode: TriggerMode = .edge,
    masked: bool,
    timer_mode: TimerMode,
    _2: u15 = 0,
};

pub const LvtMiscEntry = packed struct(u32) {
    vector: u8,
    delivery: DeliveryMode,
    _1: u1 = 0,
    /// read-only
    pending: bool = false,
    _2: u3 = 0,
    masked: bool,
    _3: u17 = 0,
};

pub const LvtErrorEntry = packed struct(u32) {
    vector: u8,
    _1: u4 = 0,
    /// read-only
    pending: bool = false,
    _2: u3 = 0,
    masked: bool,
    _3: u17 = 0,
};

pub const LapicVersion = packed struct(u32) {
    version: u8,
    _1: u8 = 0,
    max_lvt_entry: u8 = 0,
    supports_eoi_broadcast_suppression: bool,
    _2: u7 = 0,
};

pub const RegisterId = enum(u7) {
    id = 0x02,
    version = 0x03,
    eoi = 0x0B,
    spurious = 0x0F,
    isr = 0x10,
    tmr = 0x18,
    irr = 0x20,
    esr = 0x28,
    icr = 0x30,
    lvt_cmci = 0x2F,
    lvt_timer = 0x32,
    lvt_thermal_monitor = 0x33,
    lvt_perf_counter = 0x34,
    lvt_lint0 = 0x35,
    lvt_lint1 = 0x36,
    lvt_err = 0x37,
    _,
};

pub inline fn RegisterType(comptime reg: RegisterId) type {
    return switch (@intFromEnum(reg)) {
        0x02, 0x0B => u32,
        0x03 => LapicVersion,
        0x0F => SpuriousInterrupt,
        0x28 => ErrorStatusRegister,
        0x37 => LvtErrorEntry,
        0x35, 0x36 => LvtLintEntry,
        0x32 => LvtTimerEntry,
        0x34, 0x33, 0x2F => LvtMiscEntry,
        0x30 => Icr,
        0x20...0x27, 0x10...0x17, 0x18...0x1F => std.bit_set.IntegerBitSet(32),
        else => @compileError("UNSUPPORTED APIC REGISTER " ++ @tagName(reg)),
    };
}

pub const RegisterSlice = *align(16) volatile [0x40]extern struct { item: u32 align(16) };

pub const AcpiPolarity = enum(u2) {
    default,
    active_high,
    reserved,
    active_low,
};
pub const AcpiTrigger = enum(u2) {
    default,
    edge_triggered,
    reserved,
    level_triggered,
};

pub const LapicNmiPin = packed struct(u8) {
    pin: enum(u2) {
        none,
        lint0,
        lint1,
    },
    polarity: AcpiPolarity,
    trigger: AcpiTrigger,
    _: u2 = 0,
};

pub var lapic_ptr: [*]u32 = undefined;

pub var supports_eoi_broadcast_suppression: bool = false;

pub const Lapic = struct {
    id: u32,
    enabled: bool,
    online_capable: bool,
    nmi_pins: LapicNmiPin,
    uid: u32,
};

pub const Lapics = @import("util").MultiBoundedArray(Lapic, 255);
pub var lapics: Lapics = undefined;

pub var lapic_indices: [255]u8 = undefined;

pub fn init() void {
    _ = x2apic.check_enable_x2apic();
    supports_eoi_broadcast_suppression = read_register(.version).supports_eoi_broadcast_suppression;
    if (supports_eoi_broadcast_suppression) {
        log.info("EOI broadcast suppression supported", .{});
    } else {
        log.info("EOI broadcast suppression not supported", .{});
    }
    var spur: SpuriousInterrupt = read_register(.spurious);
    spur.spurious_vector = 0xFF;
    spur.apic_software_enabled = true;
    spur.suppress_eoi_broadcast = supports_eoi_broadcast_suppression;
    write_register(.spurious, spur);
}

pub inline fn read_register(comptime reg: RegisterId) RegisterType(reg) {
    std.mem.doNotOptimizeAway(&lapic_ptr);
    if (x2apic.x2apic_enabled) {
        return x2apic.read_apic_register(reg);
    } else {
        if (reg == RegisterId.icr) {
            return @bitCast((@as(u64, get_register_ptr(0x31, u32).*) << 32) | get_register_ptr(0x30, u32).*);
        } else {
            return get_register_ptr(@intFromEnum(reg), RegisterType(reg)).*;
        }
    }
}

pub fn write_register(comptime reg: RegisterId, value: RegisterType(reg)) void {
    if (x2apic.x2apic_enabled) {
        x2apic.write_apic_register(reg, value);
    } else {
        if (reg == RegisterId.icr) {
            get_register_ptr(@intFromEnum(reg) + 1, u32).* = @truncate(@as(u64, @bitCast(value)) >> 32);
            get_register_ptr(@intFromEnum(reg), u32).* = @truncate(@as(u64, @bitCast(value)));
        } else {
            get_register_ptr(@intFromEnum(reg), @TypeOf(value)).* = value;
        }
    }
}

pub var bspid: u8 = undefined;

pub inline fn get_lapic_id() u8 {
    return @truncate(read_register(.id) >> 24);
}

inline fn get_register_ptr(reg: u7, comptime T: type) *volatile T {
    return @ptrCast(lapic_ptr + (reg << 4));
}

pub fn send_ipi(ipi: Icr) void {
    std.debug.assert(!read_register(.icr).pending);
    std.debug.assert(ipi.pending == false);
    write_register(.icr, ipi);
    while (read_register(.icr).pending) {
        std.atomic.spinLoopHint();
    }
}

pub fn eoi() void {
    write_register(.eoi, 0);
}

test {
    _ = get_register_ptr;
}
