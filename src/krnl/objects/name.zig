const std = @import("std");

pub fn split(buffer: [:0]const u8) ?struct { []const u8, [:0]const u8 } {
    var index: usize = 0;
    while (buffer[index] == '/') : (index += 1) {}
    if (index > 0 and index < buffer.len) {
        index -= 1;
    } else if(index >= buffer.len) return null;

    const end = std.mem.indexOfScalarPos(u8, buffer, index + 1, '/') orelse buffer.len;
    return .{buffer[index..end], buffer[end..]};
}

/// a modified version of std.mem.TokenIterator that includes the last leading delimeter in the returned token
pub const NameTokenIterator = struct {
    buffer: [:0]const u8,
    index: usize = 0,

    fn move_to_start(self: *NameTokenIterator) void {
        while (self.buffer[self.index] == '/') : (self.index += 1) {}
        if (self.index < self.buffer.len) {
            self.index -|= 1;
        }
    }

    fn get_end_index(self: *const NameTokenIterator) usize {
        var end = self.index + 1;
        while (end < self.buffer.len and self.buffer[end] != '/') : (end += 1) {}
        return end;
    }

    pub fn peek(self: *NameTokenIterator) ?[]const u8 {
        self.move_to_start();
        const start = self.index;
        if (start >= self.buffer.len) return null;
        return self.buffer[start..self.get_end_index()];
    }

    pub fn next(self: *NameTokenIterator) ?[]const u8 {
        const item = self.peek() orelse return null;
        self.index += item.len;
        return item;
    }

    pub fn rest(self: *NameTokenIterator) [:0]const u8 {
        self.move_to_start();
        return self.buffer[self.index..];
    }

    pub fn reset(self: *NameTokenIterator) void {
        self.index = 0;
    }
};

test NameTokenIterator {
    const testing = @import("std").testing;
    const t = struct {
        fn f(ex: ?[]const u8, n: ?[]const u8) !void {
            if (ex) |s| {
                try testing.expect(n != null);
                try testing.expectEqualStrings(s, n.?);
            } else {
                try testing.expectEqual(ex, n);
            }
        }
    }.f;

    const empty = "";
    var it: NameTokenIterator = .{ .buffer = empty };
    try t(null, it.next());
    const n: [:0]const u8 = "/a/b//c/d";
    it.buffer = n;

    try t("/a", it.next());
    try t("/b//c/d", it.rest());
    try t("/b", it.next());
    try t("/c/d", it.rest());
    try t("/c", it.next());
    try t("/d", it.next());
    try t(null, it.next());
}
