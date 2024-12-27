const std = @import("std");

pub fn fieldTypes(T: type) [std.meta.fields(T).len]type {
    const fields = std.meta.fields(T);
    var types: [fields.len]type = undefined;
    for (fields, 0..) |*f, i| {
        types[i] = f.*.type;
    }
    return types;
}

fn Split(T: type, comptime pivot: usize) type {
    // TODO check A is tuple
    const types = fieldTypes(T);
    const End = std.meta.Tuple(types[pivot..]);
    if(types[pivot..].len == 0) return T;
    return std.meta.Tuple(types[0..pivot] ++ .{End});
}

fn split(tuple: anytype, comptime pivot: usize) Split(@TypeOf(tuple), pivot) {
    var result: Split(@TypeOf(tuple), pivot) = undefined;
    inline for (tuple, 0..) |value, i| {
        if (i < pivot) {
            result[i] = value;
        } else {
            result[result.len - 1][i - pivot] = value;
        }
    }
    return result;
}

test split {
    const a = .{0, 1, false, 'c', 'd'};
    try std.testing.expectEqualDeep(.{0, 1, .{false, 'c', 'd'}}, split(a, 2));
    try std.testing.expectEqualDeep(.{0, 1, false, .{'c', 'd'}}, split(a, 3));
    try std.testing.expectEqualDeep(a, split(a, 5));
}

pub fn createArgTupleUnwrapper(comptime FunctionType: type, comptime function: anytype) FunctionType {
    const fn_info = @typeInfo(FunctionType).@"fn";
    const fn_args = fn_info.params;
    const R = fn_info.return_type orelse @compileError("Function must be non-generic");

    const A = comptime b: {
        var B: [fn_args.len]type = undefined;
        for (0..fn_args.len) |i| {
            B[i] = fn_args[i].arg_type orelse @compileError("Function must be non-generic");
        }
        break :b B;
    };

    const wrapped_args = @typeInfo(@TypeOf(function)).@"fn".params;
    const split_point = wrapped_args.len - 1;

    const c = fn_info.calling_convention;

    const Wrappers = struct {
        fn fn0() callconv(c) R {
            return @call(.auto, function, split(.{}, split_point));
        }
        fn fn1(a0: A[0]) callconv(c) R {
            return @call(.auto, function, split(.{a0}, split_point));
        }
        fn fn2(a0: A[0], a1: A[1]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1 }, split_point));
        }
        fn fn3(a0: A[0], a1: A[1], a2: A[2]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2 }, split_point));
        }
        fn fn4(a0: A[0], a1: A[1], a2: A[2], a3: A[3]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3 }, split_point));
        }
        fn fn5(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4 }, split_point));
        }
        fn fn6(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5 }, split_point));
        }
        fn fn7(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6 }, split_point));
        }
        fn fn8(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7 }, split_point));
        }
        fn fn9(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8 }, split_point));
        }
        fn fn10(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9 }, split_point));
        }
        fn fn11(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 }, split_point));
        }
        fn fn12(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 }, split_point));
        }
        fn fn13(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12 }, split_point));
        }
        fn fn14(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12], a13: A[13]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13 }, split_point));
        }
        fn fn15(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12], a13: A[13], a14: A[14]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 }, split_point));
        }
        fn fn16(a0: A[0], a1: A[1], a2: A[2], a3: A[3], a4: A[4], a5: A[5], a6: A[6], a7: A[7], a8: A[8], a9: A[9], a10: A[10], a11: A[11], a12: A[12], a13: A[13], a14: A[14], a15: A[15]) callconv(c) R {
            return @call(.auto, function, split(.{ a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15 }, split_point));
        }
    };

    return switch (fn_args.len) {
        0 => Wrappers.fn0,
        1 => Wrappers.fn1,
        2 => Wrappers.fn2,
        3 => Wrappers.fn3,
        4 => Wrappers.fn4,
        5 => Wrappers.fn5,
        6 => Wrappers.fn6,
        7 => Wrappers.fn7,
        8 => Wrappers.fn8,
        9 => Wrappers.fn9,
        10 => Wrappers.fn10,
        11 => Wrappers.fn11,
        12 => Wrappers.fn12,
        13 => Wrappers.fn13,
        14 => Wrappers.fn14,
        15 => Wrappers.fn15,
        16 => Wrappers.fn16,
        else => @compileError("Unsupported number of arguments!"),
    };
}
