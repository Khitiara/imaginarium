pub fn WindowStructIndexer(comptime T: type) type {
    return struct {
        buf: []const u8,
        offset: usize = 0,

        pub fn current(self: *const @This()) *const T {
            return @ptrCast(self.buf[self.offset..]);
        }

        pub fn advance(self: *@This(), amt: usize) void {
            self.offset += amt;
        }
    };
}
pub fn WindowStructIndexerMut(comptime T: type) type {
    return struct {
        buf: []u8,
        offset: usize = 0,

        pub fn current(self: *@This()) *T {
            return @ptrCast(self.buf[self.offset..]);
        }

        pub fn advance(self: *@This(), amt: usize) void {
            self.offset += amt;
        }
    };
}
