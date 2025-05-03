const std = @import("std");
const zigimg = @import("zigimg");

fn usage(this_exe: [:0]const u8) !noreturn {
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();

    try stderr.print(
        \\Usage:
        \\  {0s} font <font png> <output file>
    , .{this_exe});

    return error.InvalidUsage;
}

fn process_font(arena: std.mem.Allocator, png: [:0]const u8, output: [:0]const u8) !void {
    // _ = arena;
    // _ = png;
    // _ = output;

    // https://github.com/zigimg/zigimg/issues/243

    var img = try zigimg.ImageUnmanaged.fromFilePath(arena, png);
    defer img.deinit(arena);

    try img.convert(arena, .grayscale1);

    const pixels = img.pixels.grayscale1;
    var one_bit_color_by_char: [128][16]std.StaticBitSet(10) = undefined;
    for(0..128) |char| {
        for(0..10) |char_x| {
            for(0..16) |char_y| {
                const row = char / 16;
                const col = char % 16;

                const x = col * 10 + char_x;
                const y = row * 16 + char_y;
                const idx = y * img.width + x;
                one_bit_color_by_char[char][char_y].setValue(9 - char_x, pixels[idx].value == 1);
            }
        }
    }

    const file = try std.fs.cwd().createFile(output, .{});
    defer file.close();
    try std.zon.stringify.serialize(.{.width = 10, .height = 16, .pixels = &one_bit_color_by_char}, .{}, file.writer());
}

fn parse_cmd(arena: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const cmd = args.next() orelse return error.InvalidUsage;
    if(std.mem.eql(u8, cmd, "font")) {
        const png = args.next() orelse return error.InvalidUsage;
        const out = args.next() orelse return error.InvalidUsage;

        try process_font(arena, png, out);
    } else {
        return error.InvalidUsage;
    }
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    const arena_alloc = arena.allocator();

    var args = try std.process.argsWithAllocator(arena_alloc);

    const this_exepath = args.next() orelse "imag-tools";

    parse_cmd(arena_alloc, &args) catch |err| switch (err) {
        error.InvalidUsage => try usage(this_exepath),
        else => return err,
    };
}