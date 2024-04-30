const cpuid = @import("cpuid.zig");
const std = @import("std");

pub fn hardware_random_supported() bool {
    return cpuid.cpuid(.type_fam_model_stepping_features, {}).features.rdrand;
}

pub fn rand(comptime T: type) T {
    return asm ("rdrand %[r]"
        : [r] "r" (-> T),
    );
}

fn fillFn(_: *anyopaque, buf: []u8) void {
    const extra = buf.len % 4;
    const times = buf.len / 4;
    for (0..times) |i| {
        @memcpy(buf[4 * i ..][0..4], std.mem.toBytes(rand(u32)));
    }
    if (extra > 0) {
        @memcpy(buf[4 * times ..][0..extra], std.mem.toBytes(rand(u32))[0..extra]);
    }
}
