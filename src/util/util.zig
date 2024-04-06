pub const checksum = @import("checksum.zig");
pub const WindowStructIndexer = @import("window_struct_indexer.zig").WindowStructIndexer;
pub const masking = @import("masking.zig");
pub const trie = @import("trie.zig");
pub const sentinel_bit_set = @import("sentinel_bit_set.zig");

const std = @import("std");
const lower_string = std.ascii.lowerString;
const assert = std.debug.assert;
const testing = std.testing;

const Log2Int = std.math.Log2Int;

// lowercases an ascii string at comptime. does not work for utf8 - this is meant mainly for debug and panic messages
// i think sentinel-terminated slices coerce to normal ones? in any case this returns a terminated one for convenience
pub inline fn lower_string_comptime(comptime str: []const u8) *const [str.len:0]u8 {
    var newArr: [str.len:0]u8 = [_:0]u8{0} ** str.len;
    const slice = lower_string(&newArr, str);
    assert(slice.len == str.len);
    return &newArr;
}

// sign extends, assuming i is typed with the correct bitsize to sign-extend from
pub inline fn signExtend(comptime T: type, i: anytype) T {
    const b = @bitSizeOf(@TypeOf(i));
    // i hope zig realizes that the local `m` in signExtendBits can be made comptime in this case
    return signExtendBits(T, b, i);
}

test signExtend {
    // 0b10 sign-extends into 0b1110
    try testing.expectEqual(14, signExtend(u4, @as(u2, 2)));
    // 0b01 sign-extends into 0b0001
    try testing.expectEqual(1, signExtend(u4, @as(u2, 1)));
}

// sign-extends based on variable bitwidth stored in a potentially larger integer type
// e.g. using a u57 for storage of a linear address on a system running only 4-level paging
// and sign-extending from the 48-bit address to the 64-bit canonical address
pub inline fn signExtendBits(comptime T: type, b: Log2Int(T), i: anytype) T {
    // no i dont know how this works
    const m: T = 1 << (b - 1);
    return ((i & ((1 << b) - 1)) ^ m) -% m;
}

test signExtendBits {
    // 0b10 sign-extends into 0b1110
    try testing.expectEqual(14, signExtendBits(u4, 2, 2));
    // 0b01 sign-extends into 0b0001
    try testing.expectEqual(1, signExtendBits(u4, 2, 1));
}

test {
    _ = lower_string_comptime;
    _ = checksum.add_checksum;
    _ = signExtend;
}
