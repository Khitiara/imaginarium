pub const sdt = @import("sdt.zig");
pub const rsdp = @import("rsdp.zig");
pub const madt = @import("madt.zig");
pub const mcfg = @import("mcfg.zig");
pub const hpet = @import("hpet.zig");
const std = @import("std");
const zuid = @import("zuid");

pub const GlobalSdtLoadError = error{
    invalid_global_table_signature,
    unexpected_global_table_signature,
    invalid_global_table_alignment,
    Overflow,
};

pub const GlobalSdtError = GlobalSdtLoadError || rsdp.RsdpError;

const ptr_from_physaddr = @import("../arch/arch.zig").ptr_from_physaddr;

pub const log = std.log.scoped(.acpi);

pub fn load_sdt_tableptr(table: *align(1) const anyopaque, expect_sig: ?sdt.Signature) !void {
    const ptr: [*]const u8 = @ptrCast(table);
    const hdr: *align(1) const sdt.SystemDescriptorTableHeader = @ptrCast(ptr);
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
                const t = ptr_from_physaddr(*align(1) const sdt.SystemDescriptorTableHeader, e);
                switch (t.signature) {
                    .APIC => try madt.read_madt(@ptrCast(t)),
                    .MCFG => mcfg.set_table(@ptrCast(t)),
                    .HPET => hpet.read_hpet(@ptrCast(t)),
                    inline .RSDT, .XSDT => |s| log.err("Self-referential {s} ACPI root table, points to {s}", .{ @tagName(sig), @tagName(s) }),
                    else => |s| {
                        log.debug("Got ACPI table with signature {s}", .{std.mem.toBytes(s)});
                    },
                }
            }
        },
        else => return error.invalid_global_table_signature,
    }
}

pub fn load_sdt(oem_id_ptr: ?*[6]u8) GlobalSdtError!void {
    const rsdp_ptr = try rsdp.locate_rsdp();
    // log.debug("rsdp: {s}", .{rsdp_ptr});
    const info = rsdp.RsdpInfo.from_rsdp(rsdp_ptr);
    try load_sdt_tableptr(info.table_addr, info.expect_signature);
    if (oem_id_ptr) |p| {
        p.* = info.oem_id;
    }
}

test {
    _ = sdt;
    _ = rsdp;
    _ = madt;
    _ = load_sdt;
}
