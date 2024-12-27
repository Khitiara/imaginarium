const std = @import("std");

pub export fn _strnlen(src: [*]const u8, size: usize) callconv(.C) usize {
    return std.mem.sliceTo(src[0..size], 0).len;
}

pub export fn _strlen(src: [*:0]const u8) callconv(.C) usize {
    return std.mem.len(src);
}