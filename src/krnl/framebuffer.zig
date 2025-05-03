const hal = @import("hal/hal.zig");
const arch = hal.arch;
const std = @import("std");
const cmn = @import("cmn");

const mm = hal.mm;

const boot = @import("boot/boot_info.zig");

pub var fb_base: [*]Pixel = undefined;
pub var fb_width: usize = undefined;
pub var fb_height: usize = undefined;
pub var fb_pitch: usize = undefined;

pub fn init() !void {
    const fb_info = &boot.framebuffers[0];

    if(fb_info.base == null) {
        fb_info.base = (try mm.map_io(fb_info.phys_addr, fb_info.mode.height * fb_info.mode.pitch * fb_info.mode.bits_per_pixel / 8, .write_combine)).ptr;
    }

    fb_base = @alignCast(@ptrCast(fb_info.base orelse return));
    fb_width = fb_info.mode.width;
    fb_height = fb_info.mode.height;
    fb_pitch = @divExact(fb_info.mode.pitch, 4);
}

pub const Pixel = packed struct(u32) {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const Block = struct {
    ptr: []const Pixel,
    width: usize,
    height: usize,
    pitch: usize,
    pub fn init_array(arr: anytype) Block {
        const child = @typeInfo(@TypeOf(arr)).Pointer;
        const rows = @typeInfo(child).Array;
        const cols = @typeInfo(rows).Array;
        comptime std.debug.assert(cols.child == Pixel);
        return Block{
            .ptr = arr,
            .width = cols.len,
            .height = rows.len,
            .pitch = cols.len,
        };
    }
};

pub fn row(y: usize) []align(1) Pixel {
    if (y > fb_height) {
        @panic("Out of bounds");
    }
    return fb_base[y * fb_pitch ..][0..fb_width];
}

pub fn fill(x: usize, y: usize, width: usize, height: usize, pixel: Pixel) void {
    if (x + width > fb_width or y + height > fb_height) {
        @panic("Out of bounds");
    }
    for (y..y + height) |r| {
        @memset(fb_base[r * fb_pitch + x ..][0..width], pixel);
    }
}

pub fn copy_slice(x: usize, y: usize, block: Block) void {
    if (x + block.width > fb_width or y + block.height > fb_height) {
        @panic("Out of bounds");
    }
    for (y..(y + block.height)) |row_num| {
        @memcpy(fb_base[row_num * fb_pitch + x ..][0..block.height], block[y * block.pitch ..][0..block.width]);
    }
}
