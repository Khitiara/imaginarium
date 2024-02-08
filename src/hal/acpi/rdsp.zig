const checksum = @import("util").checksum;
const sdt = @import("sdt.zig");

pub const Rdsp1 = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_addr: u32,

    pub usingnamespace checksum.add_checksum(Rdsp1, false);
};

pub const Rdsp2 = extern struct {
    v1: Rdsp1,
    length: u32,
    xsdt_addr: u64 align(4),
    checksum: u8,
    reserved: [3]u8,

    pub usingnamespace checksum.add_checksum(Rdsp1, false);
};

pub const RdspError = error{
    unrecognized_version,
    table_not_found,
    xsdt_on_32bit,
};

pub const RdspInfo = struct {
    oem_id: [6]u8,
    table_addr: *align(4) const anyopaque,
    expect_signature: sdt.Signature,

    pub fn from_rdsp(rdsp: Rdsp) RdspInfo {
        switch (rdsp) {
            .v1 => |v1| return .{ .oem_id = v1.oem_id, .table_addr = @ptrFromInt(v1.rsdt_addr), .expect_signature = .RSDT },
            .v2 => |v2| return .{ .oem_id = v2.v1.oem_id, .table_addr = @ptrFromInt(v2.xsdt_addr), .expect_signature = .XSDT },
        }
    }
};

pub const Rdsp = union(enum) {
    v1: *align(1) const Rdsp1,
    v2: *align(1) const Rdsp2,

    pub fn fetch_from_pointer(ptr: *const anyopaque) !Rdsp {
        const v1_ptr: *align(1) const Rdsp1 = @ptrCast(ptr);
        switch (v1_ptr.revision) {
            0 => return .{ .v1 = v1_ptr },
            2 => {
                if (@import("builtin").target.cpu.arch == .x86) return error.xsdt_on_32bit;
                return .{ .v2 = @ptrCast(ptr) };
            },
            else => return error.unrecognized_version,
        }
    }

    pub fn compute_checksum(self: *Rdsp) u8 {
        switch (self) {
            inline else => |this| return this.compute_checksum(),
        }
    }

    pub fn verify_checksum(self: *Rdsp) checksum.ChecksumErrors!void {
        switch (self) {
            inline else => |this| return this.verify_checksum(),
        }
    }
};
