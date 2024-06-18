pub const checksum = @import("checksum.zig");
pub const WindowStructIndexer = @import("window_struct_indexer.zig").WindowStructIndexer;
pub const masking = @import("masking.zig");
pub const sentinel_bit_set = @import("sentinel_bit_set.zig");
pub const extern_address = @import("externs.zig").extern_address;
pub const queue = @import("queue.zig");
pub const multi_bounded_array = @import("multi_bounded_array.zig");
pub const MultiBoundedArray = multi_bounded_array.MultiBoundedArray;
pub const MultiBoundedArrayAligned = multi_bounded_array.MultiBoundedArrayAligned;

const std = @import("std");
const lower_string = std.ascii.lowerString;
const upper_string = std.ascii.upperString;
const assert = std.debug.assert;
const testing = std.testing;

const Log2Int = std.math.Log2Int;

pub inline fn CopyPtrAttrs(
    comptime source: type,
    comptime size: std.builtin.Type.Pointer.Size,
    comptime child: type,
) type {
    const info = @typeInfo(source).Pointer;
    return @Type(.{
        .Pointer = .{
            .size = size,
            .is_const = info.is_const,
            .is_volatile = info.is_volatile,
            .is_allowzero = info.is_allowzero,
            .alignment = info.alignment,
            .address_space = info.address_space,
            .child = child,
            .sentinel = null,
        },
    });
}

pub inline fn PriorityEnum(comptime levels: comptime_int) type {
    var arr: [levels]std.builtin.Type.EnumField = undefined;
    for (0..levels) |l| {
        arr[l] = .{ .name = std.fmt.comptimePrint("p{d}", .{levels - l}), .value = l };
    }
    return @Type(.{
        .Enum = .{
            .is_exhaustive = true,
            .fields = &arr,
            .decls = &.{},
            .tag_type = std.math.IntFittingRange(0, levels - 1),
        },
    });
}

pub inline fn ReverseEnum(comptime T: type) type {
    const e = @typeInfo(T).Enum;
    const orig = e.fields;
    const cnt = orig.len;
    var arr: [cnt]std.builtin.Type.EnumField = undefined;
    for (orig, 0..) |fld, i| {
        arr[i] = fld;
        arr[i].value = cnt - arr[i].value - 1;
    }
    return @Type(.{
        .Enum = .{
            .is_exhaustive = e.is_exhaustive,
            .fields = arr,
            .decls = &.{},
            .tag_type = e.tag_type,
        },
    });
}

pub inline fn OffsetEnum(comptime T: type, comptime ofs: comptime_int) type {
    const e = @typeInfo(T).Enum;
    const orig = e.fields;
    const cnt = orig.len;
    var arr: [cnt]std.builtin.Type.EnumField = undefined;
    for (orig, 0..) |fld, i| {
        arr[i] = fld;
        arr[i].value = arr[i].value + ofs;
    }
    return @Type(.{
        .Enum = .{
            .is_exhaustive = e.is_exhaustive,
            .fields = arr,
            .decls = &.{},
            .tag_type = e.tag_type,
        },
    });
}

/// lowercases an ascii string at comptime. does not work for utf8 - this is meant mainly for debug and panic messages
/// i think sentinel-terminated slices coerce to normal ones? in any case this returns a terminated one for convenience
pub inline fn lower_string_comptime(comptime str: []const u8) *const [str.len:0]u8 {
    var newArr: [str.len:0]u8 = [_:0]u8{0} ** str.len;
    const slice = lower_string(&newArr, str);
    assert(slice.len == str.len);
    return &newArr;
}

/// uppercases an ascii string at comptime. does not work for utf8 - this is meant mainly for debug and panic messages
/// i think sentinel-terminated slices coerce to normal ones? in any case this returns a terminated one for convenience
pub inline fn upper_string_comptime(comptime str: []const u8) *const [str.len:0]u8 {
    var newArr: [str.len:0]u8 = [_:0]u8{0} ** str.len;
    const slice = upper_string(&newArr, str);
    assert(slice.len == str.len);
    return &newArr;
}

// sign extends, assuming i is typed with the correct bitsize to sign-extend from
pub inline fn signExtend(comptime T: type, i: anytype) T {
    // i hope zig realizes that the local `m` in signExtendBits can be made comptime in this case
    return signExtendBits(T, @typeInfo(@TypeOf(i)).Int.bits, i);
}

test signExtend {
    // 0b10 sign-extends into 0b1110
    try testing.expectEqual(14, signExtend(u4, @as(u2, 2)));
    // 0b01 sign-extends into 0b0001
    try testing.expectEqual(1, signExtend(u4, @as(u2, 1)));
}

/// sign-extends based on variable bitwidth stored in a potentially larger integer type
/// e.g. using a u57 for storage of a linear address on a system running only 4-level paging
/// and sign-extending from the 48-bit address to the 64-bit canonical address
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

/// equivalent to @select(T, bitset, @splat(a), @splat(b)) but operates on a bit_set mask instead of a vector mask
/// this function currently does not implement any vectorization as the kernel operates in a no-simd mode
/// but for general utils such vectorization might be implemented later, maybe as a separate helper without the splat
pub inline fn select(comptime T: type, comptime len: usize, bitset: anytype, a: T, b: T) [len]T {
    var ret: [len]T = undefined;
    for (0..len) |i| {
        if (bitset.isSet(len - i - 1)) {
            ret[i] = a;
        } else {
            ret[i] = b;
        }
    }
    return ret;
}

test {
    _ = lower_string_comptime;
    _ = checksum.add_checksum;
    _ = signExtend;
}
