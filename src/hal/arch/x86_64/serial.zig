pub const Register = enum(u3) {
    data,
    interrupt_enable,
    interrupt_ident_fifo_control,
    line_control,
    modem_control,
    line_status,
    modem_status,
    scratch,
};

pub const Parity = enum(u2) {
    odd,
    even,
    mark,
    space,
};

pub inline fn RegisterContentsRead(comptime reg: Register) type {
    return switch (reg) {
        .data => u8,
        .interrupt_enable => packed struct(u8) {
            data_available: bool,
            transmitted_empty: bool,
            break_error: bool,
            status_change: bool,
            _: u4 = 0,
        },
        .line_control => packed struct(u8) {
            /// add 5 to get actual width
            data_bits: u2,
            extra_stop_bit: bool,
            has_parity: bool,
            parity: Parity,
            set_break_enable: bool,
            divisor_latch_access: bool,
        },
        .interrupt_ident_fifo_control => packed struct(u8) {
            pending: bool,
            which: enum(u3) {
                modem_status,
                transmitted_empty,
                data_available,
                timeout = 6,
                _,
            },
            _reserved: u1 = 0,
            long_fifo_enabled: bool,
            fifo_status: enum(u2) {
                not_on_chip = 0,
                enabled_not_functioning = 2,
                enabled = 3,
            },
        },
        .modem_control => packed struct(u8) {
            data_terminal_ready: bool,
            request_send: bool,
            aux: u2,
            loopback: bool,
            autoflow: bool,
            _: u2 = 0,
        },
        .line_status => packed struct(u8) {
            data_ready: bool,
            overrun: bool,
            parity_error: bool,
            framing_error: bool,
            break_interrupt: bool,
            transmitted_empty: bool,
            data_holding_empty: bool,
            fifo_error: bool,
        },
        .modem_status => packed struct(u8) {
            data_clear_to_send: bool,
            delta_set_ready: bool,
            trailing_ring_detect: bool,
            delta_data_carrier_detect: bool,
            clear_to_send: bool,
            data_set_ready: bool,
            ring_indicator: bool,
            carrier_detect: bool,
        },
        .scratch => u8,
    };
}

pub inline fn RegisterContentsWrite(comptime reg: Register) type {
    return switch (reg) {
        .interrupt_ident_fifo_control => packed struct(u8) {
            enable: bool,
            clear_receive: bool,
            clear_transmit: bool,
            dma_mode_select: bool,
            _: u1 = 0,
            long_enable: bool,
            trigger_levels: enum(u2) {
                level_1_1,
                level_4_16,
                level_8_32,
                level_14_56,
            },
        },
        inline .data, .interrupt_enable, .line_control, .scratch, .modem_control => |r| RegisterContentsRead(r),
        else => @compileError("Cannot write to register " ++ @tagName(reg)),
    };
}

const comptimePrint = @import("std").fmt.comptimePrint;

pub inline fn outb(port: u16, comptime reg: Register, value: RegisterContentsWrite(reg)) void {
    asm volatile (
        \\ outb %[value], %[port]
        :
        : [value] "r" (value),
          [port] "N{dx}" (port + @intFromEnum(reg)),
        : "memory"
    );
}

pub inline fn inb(port: u16, comptime reg: Register) RegisterContentsRead(reg) {
    return asm volatile (
        \\ inb %[port], %[result]
        : [result] "=r" (-> RegisterContentsRead(reg)),
        : [port] "N{dx}" (port + @intFromEnum(reg)),
        : "memory"
    );
}

pub const SerialInitError = error{serial_init_failure};

pub fn init_serial(port: u16) !void {
    outb(port, .interrupt_enable, @bitCast(@as(u8, 0)));
    outb(port, .line_control, .{
        .data_bits = 3,
        .extra_stop_bit = false,
        .has_parity = false,
        .parity = .odd, // doesnt matter, has_parity is false
        .set_break_enable = false,
        .divisor_latch_access = true,
    });
    outb(port, .data, 3);
    outb(port, .interrupt_enable, @bitCast(@as(u8, 0)));
    outb(port, .line_control, .{
        .data_bits = 3,
        .extra_stop_bit = false,
        .has_parity = false,
        .parity = .odd, // doesnt matter, has_parity is false
        .set_break_enable = false,
        .divisor_latch_access = false, // turn this back off
    });
    outb(port, .interrupt_ident_fifo_control, .{
        .enable = true,
        .clear_receive = true,
        .clear_transmit = true,
        .dma_mode_select = false,
        .long_enable = false,
        .trigger_levels = .level_14_56,
    });
    outb(port, .modem_control, .{
        .data_terminal_ready = true,
        .request_send = true,
        .aux = 2,
        .loopback = false,
        .autoflow = false,
    });
    outb(port, .modem_control, .{
        .data_terminal_ready = false,
        .request_send = true,
        .aux = 3,
        .loopback = true,
        .autoflow = false,
    });
    outb(port, .data, 0xAE);
    if (inb(port, .data) != 0xAE)
        return error.serial_init_failure;

    outb(port, .modem_control, .{
        .data_terminal_ready = true,
        .request_send = true,
        .aux = 3,
        .loopback = false,
        .autoflow = false,
    });
}

pub fn writeout(comptime port: u16, value: u8) void {
    while (!inb(port, .line_status).transmitted_empty)
        asm volatile ("pause");
    outb(port, .data, value);
}

pub fn read(comptime port: u16) ?u8 {
    if (inb(port, .line_status).data_ready)
        return inb(port, .data);
    return null;
}
