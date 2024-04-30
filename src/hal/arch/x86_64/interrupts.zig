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

fn unhandled_interrupt(frame: *idt.InterruptFrame(u64)) callconv(.Win64) noreturn {
    if (std.enums.tagName(idt.Interrupt, frame.interrupt_number)) |name| {
        log.err("unhandled interrupt: 0x{X:2} ({s})", .{ @intFromEnum(frame.interrupt_number), name });
    } else {
        log.err("unhandled interrupt: 0x{X:2}", .{@intFromEnum(frame.interrupt_number)});
    }
    log.err("{}", .{frame});
    while (true) {}
}

pub fn init() void {
    idt.clear();
    log.info("disabling 8259 PIC", .{});
    disable_8259pic();
    log.info("setting up idt", .{});
    for (0..256) |i| {
        idt.add_handler(@enumFromInt(i), &unhandled_interrupt, .interrupt, 0, 0);
    }
}
