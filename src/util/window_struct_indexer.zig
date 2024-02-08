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
