const cmn = @import("cmn");
const types = cmn.types;

const std = @import("std");

const boot = @import("boot/boot_info.zig");
const limine = @import("boot/limine.zig");
const limine_reqs = @import("boot/limine_requests.zig");

const zuacpi = @import("zuacpi");

export fn __kstart() callconv(.c) noreturn {
    main() catch unreachable;
    while (true) {}
}

var early_tables_pool: [8192]u8 = undefined;

fn find_files() !struct { *const limine.File, ?*const limine.File } {
    var krnl: ?*const limine.File = null;
    var dbg: ?*const limine.File = null;

    for (limine_reqs.modules_request.response.?.modules()) |f| {
        if (std.mem.eql(u8, std.mem.span(f.cmdline), "krnl")) {
            krnl = f;
        }
        if (std.mem.eql(u8, std.mem.span(f.cmdline), "dbg")) {
            dbg = f;
        }
    }

    if (krnl) |k| {
        return .{ k, dbg };
    } else {
        @panic("Could not find kernel binary from limine");
    }
}

fn main() !void {
    try boot.dupe_bootloader_data();

    const krnl, const debug = try find_files();

    try zuacpi.uacpi.setup_early_table_access(&early_tables_pool);

    _ = krnl;
    _ = debug;
}
