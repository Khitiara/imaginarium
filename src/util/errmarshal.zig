const std = @import("std");
const unwrap = @import("unwrapArgumentTuple.zig");

pub inline fn ErrorSetEnum(comptime errorset: type) type {
    const err = @typeInfo(errorset).error_set;
    const errs = if (err) |e| e.len else 0;
    var entries: [errs + 1]std.builtin.Type.EnumField = undefined;
    for (0..errs) |i| {
        const n = err.?[i].name;
        entries[i] = .{ .name = n, .value = std.hash.Wyhash.hash(0, n) };
    }
    entries[errs] = .{
        .name = "SUCCESS",
        .value = std.hash.Wyhash.hash(0, "SUCCESS"),
    };
    return @Type(.{ .@"enum" = .{
        .tag_type = u64,
        .fields = &entries,
        .declarations = &.{},
        .is_exhaustive = true,
    } });
}

pub inline fn WrappedFunctionType(comptime fn_type: type) type {
    const f: std.builtin.Type.Fn = @typeInfo(fn_type).@"fn";
    const Ret = f.return_type orelse void;
    const t = switch (@typeInfo(Ret)) {
        .error_union => |eu| .{ ErrorSetEnum(eu.error_set), *eu.payload },
        else => return fn_type,
    };
    const NewRet = t[0];
    const Payload = t[1];
    var args: [f.params.len + 1]std.builtin.Type.Fn.Param = undefined;
    args[0] = .{ .is_generic = false, .is_noalias = false, .type = Payload };
    inline for (f.params, 1..) |p, i| {
        args[i] = p;
    }
    return @Type(.{ .@"fn" = .{
        .is_generic = false,
        .is_var_args = false,
        .return_type = NewRet,
        .calling_convention = .SysV,
        .params = &args,
    } });
}

pub inline fn wrap_function(comptime func: anytype) WrappedFunctionType(@TypeOf(func)) {
    const fn_type = @TypeOf(func);
    const f: std.builtin.Type.Fn = @typeInfo(fn_type).@"fn";
    const Ret = f.return_type orelse return func;
    const t = switch (@typeInfo(Ret)) {
        .error_union => |eu| .{ ErrorSetEnum(eu.error_set), *eu.payload },
        else => return func,
    };
    const NewRet = t[0];
    const Payload = t[1];
    const w = struct {
        fn wrapper(p: Payload, a: std.meta.ArgsTuple(fn_type)) NewRet {
            p.* = @call(.auto, func, a) catch |e| return @field(NewRet, @errorName(e));
            return .SUCCESS;
        }
    }.wrapper;
    return unwrap.createArgTupleUnwrapper(WrappedFunctionType(fn_type), w);
}

pub inline fn UnwrappedFunctionType(comptime ErrorSet: type, comptime fn_type: type) type {
    const f: std.builtin.Type.Fn = @typeInfo(fn_type).@"fn";
    const args = f.params[1..];

    return @Type(.{ .@"fn" = .{
        .is_generic = false,
        .is_var_args = false,
        .return_type = ErrorSet!@typeInfo(args[0].type).pointer.child,
        .calling_convention = .SysV,
        .params = &args,
    } });
}

pub inline fn unwrap_function(comptime ErrorSet: type, comptime func: anytype) UnwrappedFunctionType(ErrorSet, @TypeOf(func)) {
    const fn_type = @TypeOf(func);
    const f: std.builtin.Type.Fn = @typeInfo(fn_type).@"fn";
    const args = f.params[1..];
    var argument_field_list: [f.params.len - 1]type = undefined;
    inline for (args, 0..) |arg, i| {
        const T = arg.type orelse @compileError("cannot create ArgsTuple for function with an 'anytype' parameter");
        argument_field_list[i] = T;
    }
    const Args = std.meta.Tuple(&argument_field_list);
    const Payload = @typeInfo(f.params[0].type.?).pointer.child;
    const w = struct {
        fn wrapper(a: Args) ErrorSet!Payload {
            var p: Payload = undefined;
            switch (@call(.auto, func, std.meta.Tuple(&.{*Payload}){&p} ++ a)) {
                .SUCCESS => return p,
                inline else => |e| return @field(ErrorSet, @tagName(e)),
            }
        }
    }.wrapper;
    return unwrap.createArgTupleUnwrapper0(UnwrappedFunctionType(ErrorSet, fn_type), w);
}

test {
    std.testing.refAllDecls(@This());
}