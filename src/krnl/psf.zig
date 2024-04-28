const std = @import("std");
const trie = @import("util").trie;

const psf_data = @embedFile("jbmono.psf");

const expect_magic: u32 = 0x864ab572;

const header: *align(1) const Header = @ptrCast(psf_data);

test {
    try std.testing.expectEqual(expect_magic, header.magic);
}

pub const Glyph = [header.height]std.bit_set.ArrayBitSet(u8, std.mem.byte_size_in_bits * header.bytes_per_glyph / header.height);

test {
    try std.testing.expectEqual(header.bytes_per_glyph, @sizeOf(Glyph));
}

const GlyphRangeInt = std.math.IntFittingRange(0, header.glyph_count);

const offset = @sizeOf(Header) + header.glyph_count * @sizeOf(Glyph);

const unicode_entries = blk: {
    const unicode_table_raw = psf_data[offset..];
    @setEvalBranchQuota(32768);
    const T = struct { []const u8, GlyphRangeInt };
    var lst: []const T = &.{};
    var splitter = std.mem.splitScalar(u8, unicode_table_raw, 0xFF);
    var index: GlyphRangeInt = 0;
    while (splitter.next()) |entry| : (index += 1) {
        var entry_strings = std.mem.splitScalar(u8, entry, 0xFE);
        while (entry_strings.next()) |str| {
            if (str.len == 0) {
                continue;
            }
            lst = lst ++ &[1]T{T{ str, index }};
        }
    }

    break :blk std.StaticStringMap(GlyphRangeInt).initComptime(lst);
};

test {
    std.log.warn("loaded psf font with {} glyphs, table offset 0x{X}. generated {} edges in glyph-search radix trie", .{ header.glyph_count, offset, unicode_entries.kvs.len });
    for (unicode_entries.keys()) |k| {
        std.log.warn("{x: >4}: {s}", .{ k, k });
    }
}

pub const Flags = packed struct(u32) {
    has_unicode_table: bool,
    _: u31 = 0,
};

pub const Header = extern struct {
    magic: u32 = expect_magic,
    version: u32,
    header_size: u32,
    flags: Flags,
    glyph_count: u32,
    bytes_per_glyph: u32,
    height: u32,
    width: u32,
};

pub const Font = struct {
    header: Header,
    glyphs: *const [header.glyph_count]Glyph,
    // character_map: trie.StringRadixTree(GlyphRangeInt),
    character_map: std.StaticStringMap(GlyphRangeInt),

    pub fn get_glyph(self: *const Font, str: []const u8) ?struct { *const Glyph, usize } {
        if (self.character_map.getLongestPrefix(str)) |t| {
            if (t.key.len == 0) {
                return null;
            }
            return .{ &self.glyphs[t.value], t.key.len };
        } else {
            return null;
        }
    }
};

pub const font = Font{
    .header = header.*,
    .glyphs = std.mem.bytesAsValue([header.glyph_count]Glyph, psf_data[@sizeOf(Header)..][0..@sizeOf([header.glyph_count]Glyph)]),
    .character_map = unicode_entries,
};
