const idt = @import("idt.zig");
const serial = @import("serial.zig");
const std = @import("std");

const log = std.log.scoped(.interrupts);

fn disable_8259pic() void {
    // remap the pic. idk how this works
    serial.out_serial(0x20, .data, 0x11);
    serial.io_wait();
    serial.out_serial(0xA0, .data, 0x11);
    serial.io_wait();
    serial.out_serial(0x20, .interrupt_enable, @bitCast(@as(u8, 0x20)));
    serial.io_wait();
    serial.out_serial(0xA0, .interrupt_enable, @bitCast(@as(u8, 0x28)));
    serial.io_wait();
    serial.out_serial(0x20, .interrupt_enable, .{ .break_error = true });
    serial.io_wait();
    serial.out_serial(0xA0, .interrupt_enable, .{ .transmitted_empty = true });
    serial.io_wait();
    serial.out_serial(0x20, .interrupt_enable, .{ .data_available = true });
    serial.io_wait();
    serial.out_serial(0xA0, .interrupt_enable, .{ .data_available = true });
    serial.io_wait();
    // and disable the pic
    serial.out_serial(0x20, .interrupt_enable, @bitCast(@as(u8, 0xFF)));
    serial.out_serial(0xA0, .interrupt_enable, @bitCast(@as(u8, 0xFF)));
    serial.io_wait();
}

fn unhandled_interrupt(frame: *idt.InterruptFrame(u64)) callconv(.SysV) noreturn {
    if (std.enums.tagName(idt.Exception, frame.vector.exception)) |name| {
        log.err("unhandled interrupt: 0x{X: <2} ({s}) --- {}", .{ @intFromEnum(frame.vector.exception), name, frame });
    } else {
        log.err("unhandled interrupt: 0x{X: <2} --- {}", .{ @intFromEnum(frame.vector.exception), frame });
    }

    @panic("UNHANDLED EXCEPTION");
}

fn spurious(_: *idt.InterruptFrame(u64)) callconv(.SysV) void {}

fn breakpoint(frame: *idt.InterruptFrame(u64)) callconv(.SysV) void {
    std.log.debug("breakpoint: {}", .{frame});
}

pub fn init() void {
    log.info("disabling 8259 PIC", .{});
    disable_8259pic();
    log.info("setting up idt", .{});
    idt.clear(&unhandled_interrupt);
    idt.add_handler(.{ .exception = .breakpoint }, &breakpoint, .interrupt, 0, 0);
    idt.add_handler(.{ .int = @truncate(0xFF) }, &spurious, .interrupt, 0, 0);
}
