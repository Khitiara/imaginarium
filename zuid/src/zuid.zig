const std = @import("std");

const rand = std.crypto.random;

/// Pre-defined Uuid Namespaces from RFC-4122.
pub const UuidNamespace = struct {
    pub const DNS = deserialize("6ba7b810-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
    pub const URL = deserialize("6ba7b811-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
    pub const OID = deserialize("6ba7b812-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
    pub const X500 = deserialize("6ba7b814-9dad-11d1-80b4-00c04fd430c8") catch unreachable;
};

/// Convert a hexadecimal character to a numberic digit.
fn hexCharToInt(c: u8) u4 {
    switch (c) {
        '0'...'9' => return @truncate(c - '0'),
        'a'...'f' => return @truncate(c - 'a' + 10),
        'A'...'F' => return @truncate(c - 'A' + 10),
        else => return 0,
    }
}

pub const null_uuid: Uuid = @bitCast(0);

pub const Uuid = packed struct(u128) {
    node: u48,
    clock_seq_low: u8,
    clock_seq_hi_and_reserved: u8,
    time_hi: u12,
    version: u4,
    time_mid: u16,
    time_low: u32,

    pub fn toString(self: *const Uuid) [36]u8 {
        var buffer: [36]u8 = undefined;
        _ = std.fmt.bufPrint(&buffer, "{x:0>8}-{x:0>4}-{x:1}{x:0>3}-{x:0>2}{x:0>2}-{x:0>12}", .{
            self.time_low,
            self.time_mid,
            self.version,
            self.time_hi,
            self.clock_seq_hi_and_reserved,
            self.clock_seq_low,
            self.node,
        }) catch unreachable;

        return buffer;
    }

    pub fn toArray(self: Uuid) [16]u8 {
        var byte_array: [16]u8 = undefined;
        std.mem.writeInt(u128, &byte_array, @bitCast(self), .big);
        return byte_array;
    }

    pub fn eql(a: Uuid, b: Uuid) bool {
        return @as(u128, @bitCast(a)) == @as(u128, @bitCast(b));
    }
};

/// Create a Uuid object from a string
pub fn deserialize(urn: []const u8) !Uuid {
    @setEvalBranchQuota(4096);

    if (urn.len != 36 or std.mem.count(u8, urn, "-") != 4 or urn[8] != '-' or urn[13] != '-' or urn[18] != '-' or urn[23] != '-') {
        return error.InvalidUuid;
    }

    const time_low = try std.fmt.parseInt(u32, urn[0..8], 16);
    const time_mid = try std.fmt.parseInt(u16, urn[9..13], 16);
    const time_hi_and_version = try std.fmt.parseInt(u16, urn[14..18], 16);
    const clock_seq_hi_and_reserved = try std.fmt.parseInt(u8, urn[19..21], 16);
    const clock_seq_low = try std.fmt.parseInt(u8, urn[21..23], 16);
    const node = try std.fmt.parseInt(u48, urn[24..36], 16);

    return Uuid{
        .time_low = time_low,
        .time_mid = time_mid,
        .time_hi = time_hi_and_version & 0x0FFF,
        .version = time_hi_and_version >> 12,
        .clock_seq_hi_and_reserved = clock_seq_hi_and_reserved,
        .clock_seq_low = clock_seq_low,
        .node = node,
    };
}

/// Get the time since the Gregorian epoch as 100-nanosecond units.
fn getTime() u60 {
    const current_time = std.time.nanoTimestamp();
    const since_epoch_nano_seconds: i128 = current_time + 12_220_761_600_000_000_000;
    const intervals_since_gregorian_epoch = @divFloor(since_epoch_nano_seconds, 100);
    const i_60_value = intervals_since_gregorian_epoch & 0x0FFFFFFFFFFFFFFF;

    return @as(u60, @intCast(i_60_value));
}

/// Create a new Uuid
pub const new = struct {
    pub fn v1() Uuid {
        const timestamp = getTime();

        // This library uses random values for the node and clock sequence because
        // it is not easy to get the MAC address of the machine in Zig.
        // This may be implemented in the future, but for now, it is not a priority.
        var node = rand.int(u48);
        node |= 1 << 40; // Set multicast bit to distinguish from IEEE 802 MAC addresses.

        const clock_seq = @as(u16, @intCast(rand.int(u14)));

        const time_low = @as(u32, @intCast(timestamp & 0xFFFFFFFF));
        const time_mid = @as(u16, @intCast((timestamp >> 32) & 0xFFFF));

        const time_hi = @as(u12, @intCast(timestamp >> 48));

        const clock_seq_low = @as(u8, @intCast(clock_seq & 0xFF));

        var clock_seq_hi_and_reserved = @as(u8, @intCast(clock_seq >> 8));
        clock_seq_hi_and_reserved &= 0x3F;
        clock_seq_hi_and_reserved |= 0x80;

        return Uuid{
            .time_low = time_low,
            .time_mid = time_mid,
            .time_hi = time_hi,
            .version = 1,
            .clock_seq_hi_and_reserved = clock_seq_hi_and_reserved,
            .clock_seq_low = clock_seq_low,
            .node = node,
        };
    }

    pub fn v3(uuid_namespace: Uuid, name: []const u8) Uuid {
        var digest: [std.crypto.hash.Md5.digest_length]u8 = undefined;
        const namespace_str = uuid_namespace.toArray();

        var hasher = std.crypto.hash.Md5.init(.{});

        hasher.update(&namespace_str);
        hasher.update(name);

        hasher.final(&digest);

        const time_low: u32 = std.mem.readInt(u32, digest[0..4], .big);
        const time_mid: u16 = std.mem.readInt(u16, digest[4..6], .big);

        const time_hi: u12 = @truncate(std.mem.readInt(u16, digest[6..8], .big));

        var clock_seq_hi_and_reserved = digest[8];
        clock_seq_hi_and_reserved &= 0x3F;
        clock_seq_hi_and_reserved |= 0x80;

        const clock_seq_low = digest[9];
        const node = std.mem.readInt(u48, digest[10..16], .big);

        return Uuid{
            .time_low = time_low,
            .time_mid = time_mid,
            .time_hi = time_hi,
            .version = 3,
            .clock_seq_hi_and_reserved = clock_seq_hi_and_reserved,
            .clock_seq_low = clock_seq_low,
            .node = node,
        };
    }

    pub fn v4() Uuid {
        const time_low = rand.int(u32);
        const time_mid = rand.int(u16);

        const time_hi = rand.int(u12);

        var clock_seq_hi_and_reserved = rand.int(u8);
        clock_seq_hi_and_reserved &= 0x3F;
        clock_seq_hi_and_reserved |= 0x80;

        const clock_seq_low = rand.int(u8);
        const node = rand.int(u48);

        return Uuid{
            .time_low = time_low,
            .time_mid = time_mid,
            .time_hi = time_hi,
            .version = 4,
            .clock_seq_hi_and_reserved = clock_seq_hi_and_reserved,
            .clock_seq_low = clock_seq_low,
            .node = node,
        };
    }

    pub fn v5(uuid_namespace: Uuid, name: []const u8) Uuid {
        var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
        const namespace_str = uuid_namespace.toArray();

        var hasher = std.crypto.hash.Sha1.init(.{});

        hasher.update(&namespace_str);
        hasher.update(name);

        hasher.final(&digest);

        const time_low = std.mem.readInt(u32, digest[0..4], .big);
        const time_mid = std.mem.readInt(u16, digest[4..6], .big);

        const time_hi: u12 = @truncate(std.mem.readInt(u16, digest[6..8], .big));

        var clock_seq_hi_and_reserved = std.mem.nativeToBig(u8, digest[8]);
        clock_seq_hi_and_reserved &= 0x3F;
        clock_seq_hi_and_reserved |= 0x80;

        const clock_seq_low = std.mem.nativeToBig(u8, digest[9]);
        const node = std.mem.readInt(u48, digest[10..16], .big);

        return Uuid{
            .time_low = time_low,
            .time_mid = time_mid,
            .time_hi = time_hi,
            .version = 5,
            .clock_seq_hi_and_reserved = clock_seq_hi_and_reserved,
            .clock_seq_low = clock_seq_low,
            .node = node,
        };
    }
};
