const std = @import("std");
const fmt = std.fmt;
const log = std.log;
const unicode = std.unicode;
const Level = log.Level;

const uefi = std.os.uefi;

const buffer_length = 1024;
var utf16_conversion_buffer: [buffer_length]u16 = [_]u8{0} ** buffer_length;
var utf8_buffer: [buffer_length]u8 = [_]u8{0} ** buffer_length;

pub fn logFn(
    comptime message_level: Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (uefi.system_table.std_err) |err| {
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
        const utf8 = fmt.bufPrintZ(&utf8_buffer, level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
        const utf16_len = unicode.utf8ToUtf16Le(utf16_conversion_buffer, utf8) catch return;

        utf16_conversion_buffer[utf16_len] = 0;
        const utf16: [:0]u16 = utf16_conversion_buffer[0..utf16_len :0];
        err.outputString(utf16).err() catch return;
    }
}
