pub const init = @import("init.zig");
const std = @import("std");

pub const cc: std.builtin.CallingConvention = .{ .aarch64_aapcs = .{} };

comptime {
    _ = init;
}
