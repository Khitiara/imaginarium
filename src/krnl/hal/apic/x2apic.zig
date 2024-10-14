const std = @import("std");
const assert = std.debug.assert;
const cpuid = @import("../arch/cpuid.zig");
const msr = @import("../arch/msr.zig");

pub var x2apic_support: ?bool = null;
pub var x2apic_enabled: bool = false;

const log = std.log.scoped(.@"apic.x2apic");

pub inline fn supports_x2apic() bool {
    if (x2apic_support) |s| {
        return s;
    }
    const s = cpuid.cpuid(.type_fam_model_stepping_features, {}).features2.x2apic;
    log.debug("x2apic support: {}", .{s});
    x2apic_support = s;
    return s;
}

pub inline fn check_enable_x2apic() bool {
    if (x2apic_enabled) {
        @branchHint(.likely);
        return true;
    }
    if (!supports_x2apic()) {
        @branchHint(.unlikely);
        return false;
    }
    enable_x2apic();
    return true;
}

fn enable_x2apic() void {
    var base = msr.read(.apic_base);
    if (!base.apic_global_enable) {
        base.apic_global_enable = true;
        msr.write(.apic_base, base);
    }
    base.x2apic_enable = true;
    msr.write(.apic_base, base);
    x2apic_enabled = true;
}

const apic = @import("apic.zig");
const RegisterId = apic.RegisterId;
const RegisterType = apic.RegisterType;

pub fn read_apic_register(comptime register: RegisterId) RegisterType(register) {
    return @bitCast(@as(@Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(RegisterType(register)) } }), @truncate(msr.read_unsafe(0x800 + @as(u16, @intFromEnum(register))))));
}

pub fn write_apic_register(comptime register: RegisterId, value: RegisterType(register)) void {
    const v: u64 = @as(@Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(@TypeOf(value)) } }), @bitCast(value));
    msr.write_unsafe(0x800 + @intFromEnum(register), v);
}
