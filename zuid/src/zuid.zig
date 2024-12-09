const std = @import("std");

const rand = std.crypto.random;

/// Pre-defined UUID Namespaces from RFC-4122.
pub const UUIDNamespace = struct {
    pub const DNS = UUID.deserialize("6ba7b810-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
    pub const URL = UUID.deserialize("6ba7b811-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
    pub const OID = UUID.deserialize("6ba7b812-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
    pub const X500 = UUID.deserialize("6ba7b814-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
};

/// Convert a hexadecimal character to a numberic digit.
fn hexCharToInt(c: u8) u8 {
    switch (c) {
        '0'...'9' => return c - '0',
        'a'...'f' => return c - 'a' + 10,
        'A'...'F' => return c - 'A' + 10,
        else => return 0,
    }
}

pub const UUID = packed struct(u128) {
    // sets of octets, when in string form seperated by hyphens
    set_5: u48,
    set_4: u14,
    variant: u2,
    set_3: u12,
    version: u4,
    set_2: u16,
    set_1: u32,

    pub const nul: UUID = @bitCast(@as(u128, 0));
    pub const max: UUID = @bitCast(@as(u128, std.math.maxInt(u128)));

    pub fn format(self: UUID, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        const fmt_str: ?[]const u8 = comptime if (std.mem.eql(u8, fmt, "s"))
            "{x:0>8}-{x:0>4}-{x:0>4}-{x:0>4}-{x:0>12}"
        else if (std.mem.eql(u8, fmt, "S"))
            "{X:0>8}-{X:0>4}-{X:0>4}-{X:0>4}-{X:0>12}"
        else
            null;
        if (fmt_str) |s| {
            try std.fmt.format(writer, s, .{
                self.set_1,
                self.set_2,
                (self.set_3 & 0x0FFF) | (@as(u16, @intCast(self.version)) << 12),
                (self.set_4 & 0x3FFF) | (@as(u16, @intCast(self.variant)) << 14),
                self.set_5,
            });
        } else {
            if (std.mem.eql(u8, fmt, "x")) {
                try std.fmt.formatInt(@as(u128, @bitCast(self)), 16, .lower, options, writer);
            } else if (std.mem.eql(u8, fmt, "X")) {
                try std.fmt.formatInt(@as(u128, @bitCast(self)), 16, .upper, options, writer);
            } else if (std.mem.eql(u8, fmt, "d")) {
                try std.fmt.formatInt(@as(u128, @bitCast(self)), 10, .lower, options, writer);
            } else {
                try std.fmt.format(writer, "{x:0>2}", .{self.toArray()});
            }
            return;
        }
    }

    pub fn eql(first: UUID, second: UUID) bool {
        return std.mem.eql(u8, &first.toArray(), &second.toArray());
    }

    pub fn toArray(self: UUID) [16]u8 {
        var byte_array: [16]u8 = undefined;
        std.mem.writeInt(u128, &byte_array, @bitCast(self), .big);
        return byte_array;
    }

    /// Create a UUID object from a string
    pub fn deserialize(urn: []const u8) !UUID {
        @setEvalBranchQuota(4096);

        if (urn.len != 36 or std.mem.count(u8, urn, "-") != 4 or urn[8] != '-' or urn[13] != '-' or urn[18] != '-' or urn[23] != '-') {
            return error.InvalidUuid;
        }

        const set_1 = try std.fmt.parseInt(u32, urn[0..8], 16);
        const set_2 = try std.fmt.parseInt(u16, urn[9..13], 16);
        const version = try std.fmt.parseInt(u4, urn[14..15], 16);
        const set_3 = try std.fmt.parseInt(u12, urn[15..18], 16);
        const set_4_and_variant = try std.fmt.parseInt(u16, urn[19..23], 16);
        const set_4 = set_4_and_variant & 0x3FFF;
        const variant = @as(u2, @intCast(set_4_and_variant >> 14));
        const set_5 = try std.fmt.parseInt(u48, urn[24..36], 16);

        return UUID{
            .set_1 = set_1,
            .set_2 = set_2,
            .version = version,
            .set_3 = set_3,
            .variant = variant,
            .set_4 = set_4,
            .set_5 = set_5,
        };
    }

    pub fn fromArray(array: [16]u8) UUID {
        return @bitCast(std.mem.readInt(u128, &array, .big));
    }

    /// Get the time since the Gregorian epoch as 100-nanosecond units.
    fn getTime() u60 {
        const current_time = std.time.nanoTimestamp(); // Gets time relative to UTC epoch
        const gregorian_unix_offset = 122_192_928_000_000_000;
        const intervals_since_gregorian_epoch = @divFloor(current_time, 100) + gregorian_unix_offset;
        const i_60_value = intervals_since_gregorian_epoch & 0x0FFFFFFFFFFFFFFF;

        return @as(u60, @intCast(i_60_value));
    }

    /// Generate a new UUID
    pub const new = struct {
        /// Generate a Gregorian Time-based UUID
        pub fn v1() UUID {
            const timestamp = getTime();

            const time_low = @as(u32, @intCast(timestamp & 0xFFFFFFFF));
            const time_mid = @as(u16, @intCast((timestamp >> 32) & 0xFFFF));
            const version = @as(u4, @intCast(1));
            const time_high = @as(u12, @intCast(timestamp >> 48));
            const variant = @as(u2, @intCast(2));
            const clock_seq = rand.int(u14);

            // This library uses random values for the node because it is not easy to get the MAC address of the machine in Zig.
            // See https://www.rfc-editor.org/rfc/rfc9562#name-uuids-that-do-not-identify- for more information.
            var node = rand.int(u48);
            node |= 1 << 40; // Set multicast bit to distinguish from IEEE 802 MAC addresses

            var clock_seq_hi_and_reserved = @as(u8, @intCast(clock_seq >> 8));
            clock_seq_hi_and_reserved &= 0x3F;
            clock_seq_hi_and_reserved |= 0x80;

            return UUID{
                .set_1 = time_low,
                .set_2 = time_mid,
                .version = version,
                .set_3 = time_high,
                .variant = variant,
                .set_4 = clock_seq,
                .set_5 = node,
            };
        }

        pub fn v2() anyerror {
            return error.Unimplemented;
        }

        /// Generate an MD5 Name-based UUID from a namespace and a name
        pub fn v3(uuid_namespace: UUID, name: []const u8) UUID {
            var digest: [std.crypto.hash.Md5.digest_length]u8 = undefined;
            const namespace_str = uuid_namespace.toArray();

            var hasher = std.crypto.hash.Md5.init(.{});

            hasher.update(&namespace_str);
            hasher.update(name);

            hasher.final(&digest);

            const md5_high = @as(u48, @intCast(std.mem.readInt(u48, digest[0..6], .big)));
            const version = @as(u4, @intCast(3));
            const md5_mid = @as(u12, @intCast(std.mem.readInt(u16, digest[6..8], .big) & 0x0FFF));
            const variant = @as(u2, @intCast(2));
            const md5_low = @as(u64, @intCast(std.mem.readInt(u64, digest[8..16], .big)));

            return UUID{
                .set_1 = @as(u32, @intCast(md5_high & 0xFFFFFFFF)),
                .set_2 = @as(u16, @intCast((md5_high >> 32) & 0xFFFF)),
                .version = version,
                .set_3 = md5_mid,
                .variant = variant,
                .set_4 = @as(u14, @intCast((md5_low >> 48) & 0x3FFF)),
                .set_5 = @as(u48, @intCast(md5_low & 0xFFFFFFFFFFFF)),
            };
        }

        /// Generate a completely random UUID
        pub fn v4() UUID {
            const random_a = rand.int(u48);
            const version = @as(u4, @intCast(4));
            const random_b = rand.int(u12);
            const variant = @as(u2, @intCast(2));
            const random_c = rand.int(u62);

            return UUID{
                .set_1 = @as(u32, @intCast(random_a & 0xFFFFFFFF)),
                .set_2 = @as(u16, @intCast((random_a >> 32) & 0xFFFF)),
                .version = version,
                .set_3 = random_b,
                .variant = variant,
                .set_4 = @as(u14, @intCast((random_c >> 48) & 0x3FFF)),
                .set_5 = @as(u48, @intCast(random_c & 0xFFFFFFFFFFFF)),
            };
        }

        /// Generate an SHA-1 Name-based UUID from a namespace and a name
        pub fn v5(uuid_namespace: UUID, name: []const u8) UUID {
            var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
            const namespace_str = uuid_namespace.toArray();

            var hasher = std.crypto.hash.Sha1.init(.{});

            hasher.update(&namespace_str);
            hasher.update(name);

            hasher.final(&digest);

            const md5_high = @as(u48, @intCast(std.mem.readInt(u48, digest[0..6], .big)));
            const version = @as(u4, @intCast(5));
            const md5_mid = @as(u12, @intCast(std.mem.readInt(u16, digest[6..8], .big) & 0x0FFF));
            const variant = @as(u2, @intCast(2));
            const md5_low = @as(u64, @intCast(std.mem.readInt(u64, digest[8..16], .big)));

            return UUID{
                .set_1 = @as(u32, @intCast(md5_high & 0xFFFFFFFF)),
                .set_2 = @as(u16, @intCast((md5_high >> 32) & 0xFFFF)),
                .version = version,
                .set_3 = md5_mid,
                .variant = variant,
                .set_4 = @as(u14, @intCast((md5_low >> 48) & 0x3FFF)),
                .set_5 = @as(u48, @intCast(md5_low & 0xFFFFFFFFFFFF)),
            };
        }

        /// Generate a Reordered Gregorian Time-based UUID
        pub fn v6() UUID {
            const timestamp = getTime();

            const time_high = @as(u32, @intCast(timestamp & 0xFFFFFFFF));
            const time_mid = @as(u16, @intCast((timestamp >> 32) & 0xFFFF));
            const version = @as(u4, @intCast(6));
            const time_low = @as(u12, @intCast(timestamp >> 48));
            const variant = @as(u2, @intCast(2));
            const clock_seq = rand.int(u14);

            // This library uses random values for the node because it is not easy to get the MAC address of the machine in Zig.
            // See https://www.rfc-editor.org/rfc/rfc9562#name-uuids-that-do-not-identify- for more information.
            var node = rand.int(u48);
            node |= 1 << 40; // Set multicast bit to distinguish from IEEE 802 MAC addresses

            var clock_seq_hi_and_reserved = @as(u8, @intCast(clock_seq >> 8));
            clock_seq_hi_and_reserved &= 0x3F;
            clock_seq_hi_and_reserved |= 0x80;

            return UUID{
                .set_1 = time_high,
                .set_2 = time_mid,
                .version = version,
                .set_3 = time_low,
                .variant = variant,
                .set_4 = clock_seq,
                .set_5 = node,
            };
        }

        /// Generate a Unix Time-based UUID
        pub fn v7() UUID {
            const untx_ts_ms = std.time.milliTimestamp();
            const version = @as(u4, @intCast(7));
            const variant = @as(u2, @intCast(2));
            const rand_a = rand.int(u12);
            const rand_b = rand.int(u62);

            return UUID{
                .set_1 = @as(u32, @intCast(untx_ts_ms & 0xFFFFFFFF)),
                .set_2 = @as(u16, @intCast((untx_ts_ms >> 32) & 0xFFFF)),
                .version = version,
                .set_3 = rand_a,
                .variant = variant,
                .set_4 = @as(u14, @intCast((rand_b >> 48) & 0x3FFF)),
                .set_5 = @as(u48, @intCast(rand_b & 0xFFFFFFFFFFFF)),
            };
        }

        /// Generate a custom UUID with custom values
        pub fn v8(custom_a: u48, custom_b: u12, custom_c: u62) UUID {
            const version = @as(u4, @intCast(8));
            const variant = @as(u2, @intCast(2));

            return UUID{
                .set_1 = @as(u32, @intCast(custom_a & 0xFFFFFFFF)),
                .set_2 = @as(u16, @intCast((custom_a >> 32) & 0xFFFF)),
                .version = version,
                .set_3 = custom_b,
                .variant = variant,
                .set_4 = @as(u14, @intCast((custom_c >> 48) & 0x3FFF)),
                .set_5 = @as(u48, @intCast(custom_c & 0xFFFFFFFFFFFF)),
            };
        }
    };
};

const expect = std.testing.expect;

test "UUID v1" {
    const uuid = UUID.new.v1();
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(urn.len == 36);
    try expect(urn[14] == '1' and version == 1);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}

test "UUID v3" {
    const str = "4df65e20-6879-385f-ab08-bb73f8a433cb";

    const namespace = UUIDNamespace.URL;
    const url = "https://example.com";

    const uuid = UUID.new.v3(namespace, url);
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(std.mem.eql(u8, str, &urn));
    try expect(urn.len == 36);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(urn[14] == '3' and version == 3);
    try expect(variant == 2);
}

test "UUID v4" {
    const uuid = UUID.new.v4();
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(urn.len == 36);
    try expect(urn[14] == '4' and version == 4);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}

test "UUID v5" {
    const str = "5a7171ef-4fd3-5a55-a9d9-aa75c889a6d0";

    const namespace = UUIDNamespace.URL;
    const url = "https://example.com";

    const uuid = UUID.new.v5(namespace, url);
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(std.mem.eql(u8, str, &urn));
    try expect(urn.len == 36);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(urn[14] == '5' and version == 5);
    try expect(variant == 2);
}

test "UUID v6" {
    const uuid = UUID.new.v6();
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(urn.len == 36);
    try expect(urn[14] == '6' and version == 6);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}

test "UUID v7" {
    const uuid = UUID.new.v7();
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(urn.len == 36);
    try expect(urn[14] == '7' and version == 7);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}

test "UUID v8" {
    const custom_a = std.crypto.random.int(u48);
    const custom_b = std.crypto.random.int(u12);
    const custom_c = std.crypto.random.int(u62);

    const uuid = UUID.new.v8(custom_a, custom_b, custom_c);
    const version = uuid.version;
    const variant = uuid.variant;
    var urn: [36]u8 = undefined;
    _ = std.fmt.bufPrint(&urn, "{s}", .{uuid}) catch unreachable;

    try expect(urn.len == 36);
    try expect(urn[14] == '8' and version == 8);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}
