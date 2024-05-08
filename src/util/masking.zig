const std = @import("std");
const Type = std.builtin.Type;
const testing = std.testing;

// turns out the mask should be the size of the full struct anyway. might make this public later to be used in later
// truncation but whatever
// fn calc(comptime T: type, comptime field: FieldEnum(T)) type {
//     if (@typeInfo(T).Struct.layout != .Packed) {
//         @compileError("Cannot create field mask for non-packed struct");
//     }
//     const offset = @bitOffsetOf(T, @tagName(field));
//     const size = @bitSizeOf(@TypeOf(@field(@as(T, undefined), @tagName(field))));
//
//     return Int(.unsigned, offset + size);
// }

// generates a mask to isolate a field of a packed struct while keeping it shifted relative to its bit offset in the struct.
// the field's value is effectively left shifted by its bit offset in the struct and bits outside the field are masked out
pub fn makeTruncMask(comptime T: type, comptime field: []const u8) @Type(.{ .Int = .{ .signedness = .unsigned, .bits = @bitSizeOf(T) } }) {
    const offset = @bitOffsetOf(T, field);
    const size = @bitSizeOf(@TypeOf(@field(@as(T, undefined), field)));

    const size_mask = (1 << size) - 1;
    return size_mask << offset;
}

test makeTruncMask {
    const T = packed struct(u16) {
        a: u4,
        b: u3,
        c: u9,
    };
    try testing.expectEqual(0x000F, makeTruncMask(T, "a"));
    try testing.expectEqual(0x0070, makeTruncMask(T, "b"));
    try testing.expectEqual(0xFF80, makeTruncMask(T, "c"));
}
