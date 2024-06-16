const ob = @import("ob.zig");
const std = @import("std");

header: ob.ObjectRef,
children: std.StringArrayHashMapUnmanaged(*ob.Ref) = .{},

