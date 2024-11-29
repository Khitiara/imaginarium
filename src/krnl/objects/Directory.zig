const ob = @import("ob.zig");
const std = @import("std");

header: ob.Object,
children: std.StringArrayHashMapUnmanaged(*ob.Object) = .{},
