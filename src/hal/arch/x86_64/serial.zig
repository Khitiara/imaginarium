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
            data_available: bool = false,
            transmitted_empty: bool = false,
            break_error: bool = false,
            status_change: bool = false,
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

pub fn out_serial(port: u16, comptime reg: Register, value: RegisterContentsWrite(reg)) void {
    out(port + @intFromEnum(reg), @as(u8, @bitCast(value)));
}

pub fn in_serial(port: u16, comptime reg: Register) RegisterContentsRead(reg) {
    return in(port + @intFromEnum(reg), RegisterContentsRead(reg));
}

inline fn safe_port_type(T: type) type {
    switch (@typeInfo(T)) {
        .Union => |u| if (u.layout == .@"packed") {
            var t: type = undefined;
            inline for (u.fields) |f| {
                t = safe_port_type(f.type);
            }
            return t;
        },
        .Struct => |s| if (s.layout == .@"packed") {
            return safe_port_type(s.backing_integer.?);
        },
        .Int => |i| switch (i.bits) {
            8, 16, 32, 64 => return T,
            else => {},
        },
        else => {},
    }
    @compileError(@import("std").fmt.comptimePrint("Invalid io port value type {s}", .{@typeName(T)}));
}

inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "N{dx}" (port),
        : "memory"
    );
}
inline fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [value] "{ax}" (value),
          [port] "N{dx}" (port),
        : "memory"
    );
}
inline fn outd(port: u16, value: u32) void {
    asm volatile ("outd %[value], %[port]"
        :
        : [value] "{eax}" (value),
          [port] "N{dx}" (port),
        : "memory"
    );
}
inline fn outq(port: u16, value: u64) void {
    asm volatile ("outq %[value], %[port]"
        :
        : [value] "{rax}" (value),
          [port] "N{dx}" (port),
        : "memory"
    );
}

pub fn out(port: u16, value: anytype) void {
    switch (safe_port_type(@TypeOf(value))) {
        u8, i8 => outb(port, value),
        u16, i16 => outw(port, value),
        u32, i32 => outd(port, value),
        u64, i64 => outq(port, value),
        else => unreachable,
    }
}

inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
        : "memory"
    );
}

inline fn inw(port: u16) u8 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u8),
        : [port] "N{dx}" (port),
        : "memory"
    );
}

inline fn ind(port: u16) u8 {
    return asm volatile ("ind %[port], %[result]"
        : [result] "={eax}" (-> u8),
        : [port] "N{dx}" (port),
        : "memory"
    );
}

inline fn inq(port: u16) u8 {
    return asm volatile ("inq %[port], %[result]"
        : [result] "={rax}" (-> u8),
        : [port] "N{dx}" (port),
        : "memory"
    );
}

pub fn in(port: u16, T: type) T {
    return switch (safe_port_type(T)) {
        u8, i8 => @bitCast(inb(port)),
        u16, i16 => @bitCast(inw(port)),
        u32, i32 => @bitCast(ind(port)),
        u64, i64 => @bitCast(inq(port)),
        else => unreachable,
    };
}

pub const SerialInitError = error{serial_init_failure};

pub fn init_serial(port: u16) !void {
    out_serial(port, .interrupt_enable, @bitCast(@as(u8, 0)));
    out_serial(port, .line_control, .{
        .data_bits = 3,
        .extra_stop_bit = false,
        .has_parity = false,
        .parity = .odd, // doesnt matter, has_parity is false
        .set_break_enable = false,
        .divisor_latch_access = true,
    });
    out_serial(port, .data, 3);
    out_serial(port, .interrupt_enable, @bitCast(@as(u8, 0)));
    out_serial(port, .line_control, .{
        .data_bits = 3,
        .extra_stop_bit = false,
        .has_parity = false,
        .parity = .odd, // doesnt matter, has_parity is false
        .set_break_enable = false,
        .divisor_latch_access = false, // turn this back off
    });
    out_serial(port, .interrupt_ident_fifo_control, .{
        .enable = true,
        .clear_receive = true,
        .clear_transmit = true,
        .dma_mode_select = false,
        .long_enable = false,
        .trigger_levels = .level_14_56,
    });
    out_serial(port, .modem_control, .{
        .data_terminal_ready = true,
        .request_send = true,
        .aux = 2,
        .loopback = false,
        .autoflow = false,
    });
    out_serial(port, .modem_control, .{
        .data_terminal_ready = false,
        .request_send = true,
        .aux = 3,
        .loopback = true,
        .autoflow = false,
    });
    out_serial(port, .data, 0xAE);
    if (in_serial(port, .data) != 0xAE) {
        return error.serial_init_failure;
    }

    out_serial(port, .modem_control, .{
        .data_terminal_ready = true,
        .request_send = true,
        .aux = 3,
        .loopback = false,
        .autoflow = false,
    });
}

pub fn writeout(port: u16, value: u8) void {
    while (!in_serial(port, .line_status).transmitted_empty) {
        asm volatile ("pause");
    }
    out_serial(port, .data, value);
}

pub fn read(port: u16) ?u8 {
    if (in_serial(port, .line_status).data_ready) {
        return in_serial(port, .data);
    }
    return null;
}

pub fn io_wait() void {
    out_serial(0x80, .data, 0);
}
