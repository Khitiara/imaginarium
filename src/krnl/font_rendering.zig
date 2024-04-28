const psf = @import("psf.zig");
const font = psf.font;
const fb = @import("framebuffer.zig");
const std = @import("std");
const util = @import("util");

const copy_forwards = std.mem.copyForwards;

var row_ptr: [*]fb.Pixel = undefined;
pub var fg_color: fb.Pixel = .{ .red = 0xff, .green = 0xff, .blue = 0xff, .alpha = 0x00 };
pub var bg_color: fb.Pixel = .{ .red = 0x00, .green = 0x00, .blue = 0x00, .alpha = 0x00 };
pub var row: usize = 0;
pub var col: usize = 0;

var pixel_col: usize = 0;

var buf = std.fifo.LinearFifo(u8, .{ .Static = 32 }).init();

var chars_per_line: usize = 0;

pub fn init() void {
    row_ptr = fb.fb_base;
    chars_per_line = fb.fb_width / font.header.width;
    std.log.scoped(.render).info("{d} chars per line", .{chars_per_line});
}

pub fn write(str: []const u8) void {
    var s = str;
    var l = str.len;
    while (l > 0) {
        // write blocks of writableLength()
        const i = @min(s.len, buf.writableLength());
        if (i > 0) {
            buf.write(s[0..i]) catch unreachable;
            s = s[i..];
            l -= i;
        }
        // and then pump the buffer, consuming characters and writing to the screen
        pump();
        buf.realign();
    }
}

fn pump() void {
    while (buf.readableLength() > 0) {
        var newline: bool = false;
        switch (buf.peekItem(0)) {
            '\r' => {
                col = 0;
                pixel_col = 0;
                buf.discard(1);
            },
            '\n' => {
                newline = true;
                buf.discard(1);
            },
            '\t' => {
                for (0..font.header.height) |r| {
                    @memset(row_ptr[r * fb.fb_pitch + pixel_col ..][0 .. font.header.width * 4], bg_color);
                }
                pixel_col += 4 * font.header.width;
                col += 4;
                buf.discard(1);
            },
            ' ' => {
                for (0..font.header.height) |r| {
                    @memset(row_ptr[r * fb.fb_pitch + pixel_col ..][0..font.header.width], bg_color);
                }
                col += 1;
                pixel_col += font.header.width;
                buf.discard(1);
            },
            else => if (font.get_glyph(buf.readableSlice(0))) |glyph_info| {
                // font has a glyph for some prefix of our string buffer
                const glyph, const discard = glyph_info;
                for (glyph, 0..) |set, r| {
                    @memcpy(row_ptr[r * fb.fb_pitch + pixel_col ..], &util.select(fb.Pixel, font.header.width, set, fg_color, bg_color));
                }
                col += 1;
                pixel_col += font.header.width;
                buf.discard(discard);
            } else {
                const g, _ = font.get_glyph(&.{ 0xef, 0xbf, 0xbd }).?;
                for (g, 0..) |set, r| {
                    @memcpy(row_ptr[r * fb.fb_pitch + pixel_col ..], &util.select(fb.Pixel, font.header.width, set, fg_color, bg_color));
                }
                col += 1;
                pixel_col += font.header.width;
                buf.discard(1);
            },
        }
        if (newline or col > chars_per_line) {
            row += font.header.height;
            col = 0;
            pixel_col = 0;
            if (row >= fb.fb_height) {
                copy_forwards(fb.Pixel, fb.fb_base[0 .. fb.fb_height * fb.fb_pitch], fb.fb_base[font.header.height * fb.fb_pitch .. fb.fb_height * fb.fb_pitch]);
                row -= font.header.height;
            } else {
                row_ptr = row_ptr[font.header.height * fb.fb_pitch ..];
            }
        }
    }
}
