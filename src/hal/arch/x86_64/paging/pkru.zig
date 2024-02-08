const testing = @import("std").testing;

pub const PKRUEntry = packed struct(u2) {
    access_disable: bool,
    write_disable: bool,
};

pub const PKRU = enum(u32) {
    _,

    pub fn get(self: PKRU, entry: u4) PKRUEntry {
        const i = @intFromEnum(self);
        const mask = @as(u32, 0b11) << (2 * entry);
        return @bitCast(@as(u2, @truncate((i & mask) >> (2 * entry))));
    }

    test get {
        const i = 0b00_00_00_00_00_00_00_00_00_00_11_01_10_00_00_00;
        const pkru = @as(PKRU, @enumFromInt(i));
        try testing.expectEqual(PKRUEntry{ .access_disable = true, .write_disable = true }, pkru.get(5));
        try testing.expectEqual(PKRUEntry{
            .access_disable = true,
            .write_disable = false,
        }, pkru.get(4));
        try testing.expectEqual(PKRUEntry{ .access_disable = false, .write_disable = true }, pkru.get(3));
        try testing.expectEqual(PKRUEntry{
            .access_disable = false,
            .write_disable = false,
        }, pkru.get(2));
    }

    pub fn set(self: *PKRU, entry: u4, value: PKRUEntry) void {
        const i = @intFromEnum(self.*);
        const mask = ~(@as(u32, 0b11) << (2 * entry));
        self.* = @enumFromInt((i & mask) | (@as(u32, @intCast(@as(u2, @bitCast(value)))) << (2 * entry)));
    }

    test set {
        const i = 0b00_00_00_00_00_00_00_00_00_00_00_00_00_00_00_00;
        const i_2 = 0b00_00_00_00_00_00_00_00_00_00_00_00_10_00_00_00;
        const i_3 = 0b00_00_00_00_00_00_00_00_00_00_00_01_10_00_00_00;
        const i_4 = 0b00_00_00_00_00_00_00_00_00_00_11_01_10_00_00_00;
        var pkru = @as(PKRU, @enumFromInt(i));
        pkru.set(3, PKRUEntry{ .access_disable = false, .write_disable = true });
        try testing.expectEqual(i_2, @intFromEnum(pkru));
        pkru.set(4, PKRUEntry{ .access_disable = true, .write_disable = false });
        try testing.expectEqual(i_3, @intFromEnum(pkru));
        pkru.set(5, PKRUEntry{ .access_disable = true, .write_disable = true });
        try testing.expectEqual(i_4, @intFromEnum(pkru));
    }
};

pub fn readPKRU() PKRU {
    return @enumFromInt(asm volatile (
        \\ xorl ecx, ecx
        \\ rdpkru
        : [out] "={eax}" (-> u32),
        :
        : "edx", "ecx"
    ));
}

pub fn writePKRU(value: PKRU) void {
    const i = @intFromEnum(value);
    asm volatile (
        \\ xorl ecx, ecx
        \\ xorl edx, edx
        \\ wrpkru
        :
        : [in] "eax" (i),
        : "edx", "ecx", "memory"
    );
}

test {
    _ = readPKRU;
    _ = @as(PKRU, @enumFromInt(0));
}
