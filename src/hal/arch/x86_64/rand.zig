const cpuid = @import("cpuid.zig");
const std = @import("std");

pub fn hardware_random_supported() bool {
    return cpuid.cpuid(.type_fam_model_stepping_features, {}).features.rdrand;
}

pub fn rand() u32 {
    return asm ("rdrand %[r]"
        : [r] "=r" (-> u32),
    );
}

pub fn fill(buf: []u8) void {
    const extra = buf.len % 4;
    const times = buf.len / 4;
    for (0..times) |i| {
        @memcpy(buf[4 * i ..][0..4], &std.mem.toBytes(rand()));
    }
    if (extra > 0) {
        @memcpy(buf[4 * times ..][0..extra], std.mem.toBytes(rand())[0..extra]);
    }
}

fn fillFn(_: *anyopaque, buf: []u8) void {
    fill(buf);
}
