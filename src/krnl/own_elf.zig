const std = @import("std");
const elf = std.elf;
const config = @import("config");
const hal = @import("root").hal;
const arch = hal.arch;

var elf_stream: std.io.FixedBufferStream([]const u8) = undefined;
var hdr: elf.Header = undefined;

pub fn get_tls_size(size: *usize, initial_state: *[]const u8) !void {
    const slice = arch.ptr_from_physaddr(*const [config.max_elf_size]u8, 0x8E00);
    elf_stream = std.io.fixedBufferStream(slice);
    hdr = try elf.Header.read(&elf_stream);
    var ph_iter = hdr.program_header_iterator(elf_stream);
    const tls_hdr = while (try ph_iter.next()) |phdr| {
        if (phdr.p_type == elf.PT_TLS) {
            break phdr;
        }
    } else {
        return error.no_tls_segment;
    };

    size.* = tls_hdr.p_memsz;
    const start = @extern([*]u8, .{ .name = "__tls_data_start__" });
    const end = @intFromPtr(@extern([*]const u8, .{ .name = "__tls_data_end__" }));
    const init_len = end - @intFromPtr(start);
    const bytes = start[0..init_len];
    @memcpy(bytes, slice[tls_hdr.p_offset..][0..tls_hdr.p_filesz]);
    std.log.debug("initial tls at {*}, len {x}", .{ start, init_len });
    try @import("debug.zig").dump_hex(bytes);
    initial_state.* = bytes;
}
