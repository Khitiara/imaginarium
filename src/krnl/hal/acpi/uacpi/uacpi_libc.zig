const std = @import("std");

pub export fn _memcpy(dest: [*]u8, src: [*]u8, size: usize) callconv(.C) [*]u8 {
    @memcpy(dest[0..size], src[0..size]);
    return dest;
}

pub export fn _memset(dest: [*c]u8, value: c_int, size: usize) callconv(.C) [*c]u8 {
    @memset(dest[0..size], @intCast(value));
    return dest;
}

pub export fn _memmove(dest: [*]u8, src: [*]u8, size: usize) callconv(.C) [*]u8 {
    if(@intFromPtr(dest) > @intFromPtr(src)) {
        std.mem.copyBackwards(u8, dest[0..size], src[0..size]);
    } else {
        std.mem.copyForwards(u8, dest[0..size], src[0..size]);
    }
    return dest;
}

pub export fn _strnlen(src: [*]const u8, size: usize) callconv(.C) usize {
    return std.mem.sliceTo(src[0..size], 0).len;
}

pub export fn _strlen(src: [*:0]const u8) callconv(.C) usize {
    return std.mem.len(src);
}