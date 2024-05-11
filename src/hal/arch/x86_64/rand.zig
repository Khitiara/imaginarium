const cpuid = @import("cpuid.zig");
const std = @import("std");
const x86_64 = @import("x86_64.zig");

pub fn hardware_random_supported() bool {
    return cpuid.cpuid(.type_fam_model_stepping_features, {}).features.rdrand;
}

pub fn hardware_getseed_supported() bool {
    return cpuid.cpuid(.feature_flags, {}).flags3.rdseed;
}

pub fn rdseed() u32 {
    return asm volatile (
        \\ _rdseed_1:
        \\     rdseed %[r]
        \\     jnc _rdseed_1
        : [r] "=r" (-> u32),
    );
}

pub fn rdrand() u32 {
    return asm volatile (
        \\ _rdrand_1:
        \\     rdrand %[r]
        \\     jnc _rdrand_1
        : [r] "=r" (-> u32),
    );
}

pub fn fill(buf: []u8) void {
    const extra = buf.len % 4;
    const times = buf.len / 4;
    for (0..times) |i| {
        @memcpy(buf[4 * i ..][0..4], &std.mem.toBytes(rdrand()));
    }
    if (extra > 0) {
        @memcpy(buf[4 * times ..][0..extra], std.mem.toBytes(rdrand())[0..extra]);
    }
}

pub fn fill_secure(buf: []u8) void {
    const extra = buf.len % 4;
    const times = buf.len / 4;
    for (0..times) |i| {
        @memcpy(buf[4 * i ..][0..4], &std.mem.toBytes(rdseed()));
    }
    if (extra > 0) {
        @memcpy(buf[4 * times ..][0..extra], std.mem.toBytes(rdseed())[0..extra]);
    }
}

fn fill_fn(_: *anyopaque, buf: []u8) void {
    fill(buf);
}

fn secure_fill_fn(_: *anyopaque, buf: []u8) void {
    fill_secure(buf);
}
