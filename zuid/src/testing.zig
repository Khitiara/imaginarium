const std = @import("std");
const zuid = @import("zuid");

const expect = std.testing.expect;

test "UUID v1" {
    const uuid = zuid.new.v1();
    const version = (uuid.time_hi_and_version & 0xF000) >> 12;
    const variant = (uuid.clock_seq_hi_and_reserved & 0xC0) >> 6;
    const urn = uuid.toString();
    try expect(urn.len == 36);
    try expect(urn[14] == '1' and version == 1);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}

test "UUID v3" {
    const str = "68794df6-5e20-385f-ab08-bb73f8a433cb";

    const namespace = zuid.UuidNamespace.URL;
    const url = "https://example.com";

    const uuid = zuid.new.v3(namespace, url);
    const urn = uuid.toString();
    const version = (uuid.time_hi_and_version & 0xF000) >> 12;
    const variant = (uuid.clock_seq_hi_and_reserved & 0xC0) >> 6;
    try expect(std.mem.eql(u8, str, &urn));
    try expect(urn.len == 36);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(urn[14] == '3' and version == 3);
    try expect(variant == 2);
}

test "UUID v4" {
    const uuid = zuid.new.v4();
    const version = (uuid.time_hi_and_version & 0xF000) >> 12;
    const variant = (uuid.clock_seq_hi_and_reserved & 0xC0) >> 6;
    const urn = uuid.toString();
    try expect(urn.len == 36);
    try expect(urn[14] == '4' and version == 4);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(variant == 2);
}

test "UUID v5" {
    const str = "4fd35a71-71ef-5a55-a9d9-aa75c889a6d0";

    const namespace = zuid.UuidNamespace.URL;
    const url = "https://example.com";

    const uuid = zuid.new.v5(namespace, url);
    const urn = uuid.toString();
    const version = (uuid.time_hi_and_version & 0xF000) >> 12;
    const variant = (uuid.clock_seq_hi_and_reserved & 0xC0) >> 6;
    try expect(std.mem.eql(u8, str, &urn));
    try expect(urn.len == 36);
    try expect(std.mem.count(u8, &urn, "-") == 4);
    try expect(urn[8] == '-' and urn[13] == '-' and urn[18] == '-' and urn[23] == '-');
    try expect(urn[14] == '5' and version == 5);
    try expect(variant == 2);
}
