pub const entries = @import("paging/page_table_entry.zig");
pub const pkru = @import("paging/pkru.zig");

test {
    @import("std").testing.refAllDecls(entries);
}