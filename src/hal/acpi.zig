pub const sdt = @import("acpi/sdt.zig");
pub const rsdp = @import("acpi/rsdp.zig");
pub const madt = @import("acpi/madt.zig");
const std = @import("std");

pub const GlobalSdtLoadError = error{
    invalid_global_table_signature,
    unexpected_global_table_signature,
    invalid_global_table_alignment,
};

pub const GlobalSdtError = GlobalSdtLoadError || rsdp.RsdpError;

pub fn load_sdt_tableptr(table: *align(4) const anyopaque, expect_sig: ?sdt.Signature) !void {
    const ptr: [*]align(4) const u8 = @ptrCast(table);
    const hdr: *const sdt.SystemDescriptorTableHeader = @ptrCast(ptr);
    if (hdr.signature != expect_sig) {
        return error.unexpected_global_table_signature;
    }
    switch (hdr.signature) {
        inline .RSDT, .XSDT => |sig| {
            const EntryType = switch (sig) {
                .RSDT => u32,
                .XSDT => u64,
                else => unreachable,
            };
            const begin = comptime std.mem.alignForward(usize, @sizeOf(sdt.SystemDescriptorTableHeader), 4);
            if (!std.mem.isAligned(hdr.length, 4)) {
                return error.invalid_global_table_alignment;
            }
            const slice = std.mem.bytesAsSlice(EntryType, ptr[begin..hdr.length]);

            for (slice) |e| {
                const t: *const sdt.SystemDescriptorTableHeader = @ptrFromInt(e);
                switch (t.signature) {
                    .APIC => madt.read_madt(@ptrCast(t)),
                    else => {},
                }
            }
        },
        else => return error.invalid_global_table_signature,
    }
}

fn load_sdt_bios(oem_id_ptr: ?*[6]u8) GlobalSdtError!void {
    const rsdp_ptr = try rsdp.locate_rsdp_bios();
    const info = rsdp.RsdpInfo.from_rsdp(rsdp_ptr);
    try load_sdt_tableptr(info.table_addr, info.expect_signature);
    if (oem_id_ptr) |p| {
        p.* = info.oem_id;
    }
}

fn load_sdt_efi(oem_id_ptr: ?*[6]u8) GlobalSdtError!void {
    _ = oem_id_ptr;
    @panic("not implemented");
}

pub const load_sdt: fn(oem_id_ptr: ?*[6]u8) GlobalSdtError!void = if (@import("config").rsdp_search_bios) load_sdt_bios else load_sdt_efi;

test {
    _ = sdt;
    _ = rsdp;
    _ = madt;
    _ = load_sdt;
}
