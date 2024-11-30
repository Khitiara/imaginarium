const real = @import("real.zig");
const std = @import("std");

const Dap = extern struct {
    size: u16,
    count: u16,
    offset: u16,
    segment: u16,
    lba: u64,
};

var rm_xfer_buf: [4096]u8 linksection(".realmode") = undefined;

pub fn read_sectors(drive: u8, buf: []u8, block: u64, sectors: u64) !void {
    @memset(&rm_xfer_buf, 0);
    var dap: Dap = .{
        .size = 16,
        .count = sectors,
        .segment = real.rm_seg(&rm_xfer_buf),
        .offset = real.rm_ofs(&rm_xfer_buf),
        .lba = block,
    };

    var r: real.RealModeRegs = std.mem.zeroes(real.RealModeRegs);
    r.eax = 0x4200;
    r.edx = drive;
    r.esi = real.rm_ofs(&dap);
    r.ds = real.rm_seg(&dap);

    real.rm_int(0x13, &r, &r);

    if(r.eflags.carry) return error.BiosDiskFailure;
    @memcpy(buf, &rm_xfer_buf[0..buf.len]);
}
