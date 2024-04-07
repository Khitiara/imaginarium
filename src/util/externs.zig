pub inline fn extern_address(comptime name: []const u8) *anyopaque {
    return @extern(*anyopaque, .{ .name = name });
}
