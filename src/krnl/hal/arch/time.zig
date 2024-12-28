var bus_core_freq: ?u64 = null;
var itsc: bool = undefined;
var tsc_ratio: ?struct { numerator: u32, denominator: u32 } = null;
var computed_tsc_freq_khz: ?u64 = null;

const cpuid = @import("cpuid.zig");
const std = @import("std");
const hypervisor = @import("../hypervisor.zig");

const log = std.log.scoped(.time);

pub fn init_timing() void {
    itsc = cpuid.cpuid(.capabilities, {}).enhanced_power_management.itsc;

    if (hypervisor.present) {
        const hypervisor_timings = cpuid.cpuid(.hypervisor_frequencies, {});
        bus_core_freq = hypervisor_timings.bus_freq_khz;
        computed_tsc_freq_khz = hypervisor_timings.tsc_freq_khz;
        log.debug("got frequency information from hypervisor: TSC {d}kHz, bus {d}kHz", .{ hypervisor_timings.tsc_freq_khz, hypervisor_timings.bus_freq_khz });
    } else {
        const freqs = cpuid.cpuid(.freq_1, {});
        if (freqs.core_freq != 0) {
            bus_core_freq = freqs.core_freq / 1000;
        }
        if (freqs.numerator != 0) {
            tsc_ratio = .{ .numerator = freqs.numerator, .denominator = freqs.denominator };
        }
        log.debug("TSC frequency information: {d} * {d} / {d} (itsc: {})", .{ freqs.core_freq, freqs.numerator, freqs.denominator, itsc });

        if (freqs.denominator == 0 or freqs.numerator == 0) {
            const freqs2 = cpuid.cpuid(.freq_2, {});
            log.debug("CORE frequency information: core base {d}, core max {d}, bus ref {d}", .{ freqs2.core_base, freqs2.core_max, freqs2.bus_reference });
        } else {
            var buf_usize: usize = freqs.core_freq;
            buf_usize *= freqs.numerator;
            buf_usize /= freqs.denominator;
            computed_tsc_freq_khz = buf_usize / 1000;
        }
    }
}

pub inline fn rdtsc() u64 {
    return asm volatile (
        \\ rdtsc
        \\ shlq $32, %rax
        \\ shrdq $32, %rdx, %rax
        : [tsc] "={rax}" (-> u64),
        :
        : "edx"
    );
}

pub inline fn rdtscp() struct { tsc: u64, pid: u32 } {
    var tsc: u64 = undefined;
    var pid: u32 = undefined;
    asm volatile (
        \\ rdtscp
        \\ shlq $32, %rax
        \\ shrdq $32, %rdx, %rax
        : [tsc] "={rax}" (tsc),
          [pid] "={ecx}" (pid),
        :
        : "edx"
    );
    return .{ .tsc = tsc, .pid = pid };
}

pub fn ns_since_boot_tsc() !i128 {
    if (computed_tsc_freq_khz) |freq| {
        const tsc: i128 = rdtsc();
        return @divFloor(tsc *% std.time.ns_per_ms, freq);
    }
    return error.NoTscFreq;
}
