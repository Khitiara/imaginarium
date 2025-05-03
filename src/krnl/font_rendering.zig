const fb = @import("framebuffer.zig");
const std = @import("std");
const util = @import("util");

/// https://leickh.itch.io/monofont-10x16-png
const font: struct { width: usize, height: usize, pixels: [128][16]std.StaticBitSet(10) } = @import("font");

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
    chars_per_line = fb.fb_width / font.width;
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
        switch (buf.readItem(0)) {
            '\r' => {
                col = 0;
                pixel_col = 0;
            },
            '\n' => {
                newline = true;
            },
            '\t' => {
                for (0..font.height) |r| {
                    @memset(row_ptr[r * fb.fb_pitch + pixel_col ..][0 .. font.width * 4], bg_color);
                }
                pixel_col += 4 * font.width;
                col += 4;
            },
            else => |c| if (c < 128) {
                const glyph = font.pixels[c];
                for (0..font.height) |r| {
                    @memcpy(row_ptr[r * fb.fb_pitch + pixel_col ..], &util.select(fb.Pixel, font.width, glyph[r], fg_color, bg_color));
                }
                col += 1;
                pixel_col += font.width;
            },
        }
        if (newline or col > chars_per_line) {
            row += font.height;
            col = 0;
            pixel_col = 0;
            if (row >= fb.fb_height) {
                copy_forwards(fb.Pixel, fb.fb_base[0 .. fb.fb_height * fb.fb_pitch], fb.fb_base[font.height * fb.fb_pitch .. fb.fb_height * fb.fb_pitch]);
                row -= font.height;
            } else {
                row_ptr = row_ptr[font.height * fb.fb_pitch ..];
            }
        }
    }
}
