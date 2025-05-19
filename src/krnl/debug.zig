const std = @import("std");
const hal = @import("hal/hal.zig");
const arch = hal.arch;
const puts = arch.puts;
pub const SerialWriter = arch.SerialWriter;

const log = std.log.default;

inline fn fixup_stack_addr(a: usize) usize {
    return if (a == 0) 0 else a - 1;
}

pub fn print_stack_trace(ip: ?usize, trace: *std.builtin.StackTrace) !void {
    const writer = SerialWriter.writer();
    {
        if (ip) |rip| {
            try writer.print("    at {x:16}\n", .{rip});
        }
        var frame_index: usize = 0;
        var frames_left: usize = @min(trace.index, trace.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % trace.instruction_addresses.len;
        }) {
            try writer.print("    at {x:16}\n", .{trace.instruction_addresses[frame_index] -| 1});
        }
    }
    {
        const debug_info = try std.debug.getSelfDebugInfo();
        if (ip) |rip| {
            try std.debug.printSourceAtAddress(debug_info, writer, rip -| 1, .no_color);
        }
        var frame_index: usize = 0;
        var frames_left: usize = @min(trace.index, trace.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % trace.instruction_addresses.len;
        }) {
            try std.debug.printSourceAtAddress(debug_info, writer, trace.instruction_addresses[frame_index] -| 1, .no_color);
        }
    }
}

pub fn dump_stack_trace(logger: anytype, ret_addr: ?usize) !void {
    logger.debug("current stack trace: ", .{});
    var addrs: [16]usize = undefined;
    var trace: std.builtin.StackTrace = .{
        .instruction_addresses = &addrs,
        .index = 0,
    };
    std.debug.captureStackTrace(null, &trace);
    try print_stack_trace(ret_addr orelse @returnAddress(), &trace);
}

pub fn print_err_trace(logger: anytype, msg: []const u8, err: anyerror, error_return_trace: ?*std.builtin.StackTrace) !void {
    logger.err("ERROR {s} {s}, trace:", .{ msg, @errorName(err) });
    if (error_return_trace) |stk| {
        try print_stack_trace(null, stk);
    } else {
        log.err("    ---", .{});
    }
}

pub fn panic(msg: []const u8, ret_addr: ?usize) noreturn {
    log.err("PANIC {s}, RETURN={X:0>16}", .{ msg, ret_addr orelse 0 });
    dump_stack_trace(log, ret_addr) catch {};
    while (true) {
        // @breakpoint();
    }
}

pub fn dump_hex(bytes: []const u8) !void {
    try dump_hex_config(bytes, @import("root").tty);
}

pub fn dump_hex_config(bytes: []const u8, ttyconf: std.io.tty.Config) !void {
    const writer = SerialWriter.writer();
    var chunks = std.mem.window(u8, bytes, 16, 16);
    while (chunks.next()) |window| {
        // 1. Print the address.
        const address = (@intFromPtr(bytes.ptr) + 0x10 * (try std.math.divCeil(usize, chunks.index orelse bytes.len, 16))) - 0x10;
        try ttyconf.setColor(writer, .dim);
        // We print the address in lowercase and the bytes in uppercase hexadecimal to distinguish them more.
        // Also, make sure all lines are aligned by padding the address.
        try writer.print("{x:0>[1]}  ", .{ address, @sizeOf(usize) * 2 });
        try ttyconf.setColor(writer, .reset);

        // 2. Print the bytes.
        for (window, 0..) |byte, index| {
            try writer.print("{X:0>2} ", .{byte});
            if (index == 7) try writer.writeByte(' ');
        }
        try writer.writeByte(' ');
        if (window.len < 16) {
            var missing_columns = (16 - window.len) * 3;
            if (window.len < 8) missing_columns += 1;
            try writer.writeByteNTimes(' ', missing_columns);
        }

        // 3. Print the characters.
        for (window) |byte| {
            if (std.ascii.isPrint(byte)) {
                try writer.writeByte(byte);
            } else {
                // Related: https://github.com/ziglang/zig/issues/7600

                // Let's print some common control codes as graphical Unicode symbols.
                // We don't want to do this for all control codes because most control codes apart from
                // the ones that Zig has escape sequences for are likely not very useful to print as symbols.
                switch (byte) {
                    '\n' => try writer.writeAll("␊"),
                    '\r' => try writer.writeAll("␍"),
                    '\t' => try writer.writeAll("␉"),
                    else => try writer.writeByte('.'),
                }
            }
        }
        try writer.writeByte('\n');
    }
}
