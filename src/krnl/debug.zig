const std = @import("std");
const hal = @import("hal");
const arch = hal.arch;
const puts = arch.puts;

pub const SerialWriter = struct {
    const WriteError = error{};
    pub const Writer = std.io.GenericWriter(*const anyopaque, error{}, typeErasedWriteFn);

    fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) error{}!usize {
        _ = context;
        puts(bytes);
        return bytes.len;
    }

    pub fn writer() Writer {
        return .{ .context = undefined };
    }
};

const log = std.log.default;

pub fn print_stack_trace(logger: anytype, trace: *std.builtin.StackTrace) void {
    var i: usize = 0;
    var frame_index: usize = 0;
    var frames_left: usize = @min(trace.index, trace.instruction_addresses.len);
    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % trace.instruction_addresses.len;
        i += 1;
    }) {
        const return_address = trace.instruction_addresses[frame_index];
        logger.debug("   at   {d: <4}: {x:0>16}", .{ i, return_address });
    }
}

pub fn dump_stack_trace(logger: anytype, ret_addr: ?usize) void {
    logger.debug("current stack trace: ", .{});
    var addrs: [16]usize = undefined;
    var trace: std.builtin.StackTrace = .{
        .instruction_addresses = &addrs,
        .index = 0,
    };
    std.debug.captureStackTrace(ret_addr orelse @returnAddress(), &trace);
    print_stack_trace(logger, &trace);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    log.err("PANIC {s}, RETURN={X:0>16}; error return trace:", .{ msg, ret_addr orelse 0 });
    if (error_return_trace) |stk| {
        print_stack_trace(log, stk);
    } else {
        log.err("    ---", .{});
    }
    dump_stack_trace(log, ret_addr);
    while (true) {
        @breakpoint();
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
