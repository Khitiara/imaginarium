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
    var r: u32 = 0;
    while (!x86_64.flags().carry) {
        r = asm ("rdseed %[r]"
            : [r] "=r" (-> u32),
        );
    }
    return r;
}

pub fn rdrand() u32 {
    var r: u32 = 0;
    while (!x86_64.flags().carry) {
        r = asm ("rdrand %[r]"
            : [r] "=r" (-> u32),
        );
    }
    return r;
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

fn fillFn(_: *anyopaque, buf: []u8) void {
    fill(buf);
}
