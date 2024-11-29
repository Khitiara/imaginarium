const uacpi = @import("uacpi/uacpi.zig");

comptime {
    _ = @import("uacpi/uacpi_libc.zig");
    _ = @import("uacpi/shims.zig");
}