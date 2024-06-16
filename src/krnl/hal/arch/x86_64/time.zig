var bus_core_freq: ?u32 = null;
var itsc: bool = undefined;
var tsc_ratio: ?struct { numerator: u32, denominator: u32 } = null;

const cpuid = @import("cpuid.zig");
const std = @import("std");

const log = std.log.scoped(.time);

pub fn init_timing() void {
    itsc = cpuid.cpuid(.capabilities, {}).enhanced_power_management.itsc;
    const freqs = cpuid.cpuid(.freq_1, {});
    if (freqs.core_freq != 0) {
        bus_core_freq = freqs.core_freq;
    }
    if (freqs.numerator != 0) {
        tsc_ratio = .{ .numerator = freqs.numerator, .denominator = freqs.denominator };
    }
    log.debug("TSC frequency information: {d} * {d} / {d} (itsc: {})", .{ freqs.core_freq, freqs.numerator, freqs.denominator, itsc });

    if(freqs.denominator == 0 or freqs.numerator == 0) {
        const freqs2 = cpuid.cpuid(.freq_2, {});
        log.debug("CORE frequency information: core base {d}, core max {d}, bus ref {d}", .{ freqs2.core_base, freqs2.core_max, freqs2.bus_reference });
    }
}

pub inline fn rdtsc() u64 {
    var eax: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("rdtsc"
        : [eax] "={eax}" (eax),
          [edx] "={edx}" (edx),
    );
    return (@as(u64, edx) << 32) | eax;
}
