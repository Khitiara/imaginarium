const std = @import("std");

const cmn = @import("cmn");
const bootelf = cmn.bootelf;

const hal = @import("hal/hal.zig");
const util = @import("util");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;
const puts = arch.puts;

const fb = @import("framebuffer.zig");
const font_rendering = @import("font_rendering.zig");
const debug = @import("debug.zig");
const smp = @import("smp.zig");

const log = std.log.default;

pub const tty: std.io.tty.Config = .no_color;

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    tty.setColor(debug.SerialWriter.writer(), switch (message_level) {
        .debug => .dim,
        .err => .red,
        .warn => .yellow,
        .info => .reset,
    }) catch unreachable;
    tty.setColor(debug.SerialWriter.writer(), .bold) catch unreachable;
    puts(util.upper_string_comptime(message_level.asText()));
    tty.setColor(debug.SerialWriter.writer(), .reset) catch unreachable;
    if (scope != .default) {
        tty.setColor(debug.SerialWriter.writer(), .dim) catch unreachable;
        puts(" (");
        puts(util.lower_string_comptime(@tagName(scope)));
        puts(")");
        tty.setColor(debug.SerialWriter.writer(), .reset) catch unreachable;
    }
    puts(": ");
    debug.SerialWriter.writer().print(format, args) catch unreachable;
    if (format.len == 0 or format[format.len - 1] != '\n') {
        puts("\n");
    }
}

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = arch.vmm.raw_page_allocator.allocator();
    };
};

pub const Panic = struct {
    pub const call = debug.panic;
    pub const sentinelMismatch = std.debug.FormattedPanic.sentinelMismatch;
    pub const unwrapError = std.debug.FormattedPanic.unwrapError;
    pub const outOfBounds = std.debug.FormattedPanic.outOfBounds;
    pub const startGreaterThanEnd = std.debug.FormattedPanic.startGreaterThanEnd;
    pub const inactiveUnionField = std.debug.FormattedPanic.inactiveUnionField;
    pub const messages = std.debug.FormattedPanic.messages;
};

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
    .crypto_always_getrandom = true,
    .cryptoRandomSeed = arch.rand.fill_secure,
};

/// the true entry point is __kstart and is exported by global asm in `hal/arch/{arch}/init.zig`
/// __kstart is responsible for stack setup and jumps unconditionally into __kstart2
/// __kstart2 is responsible for calling main and handling any zig errors returned from there
/// as well as entering the final infinite loop if everything worked successfully
export fn __kstart2(ldr_info: *bootelf.BootelfData) callconv(arch.cc) noreturn {
    main(ldr_info) catch |e| {
        std.builtin.panicUnwrapError(@errorReturnTrace(), e);
    };
}

const uacpi = @import("hal/acpi/uacpi/uacpi.zig");
const zuacpi = @import("hal/acpi/zuacpi.zig");

noinline fn main(ldr_info: *bootelf.BootelfData) anyerror!noreturn {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    try arch.platform_init(ldr_info.memory_map());
    // ldr_info.entries = arch.ptr_from_physaddr([*]hal.memory.MemoryMapEntry, @intFromPtr(ldr_info.entries));
    const page, const gpa = try arch.smp.init();
    try smp.allocate_lcbs(page);
    try smp.enter_threading(page, gpa);


    log.debug("current gs base: {x}", .{arch.msr.read(.gs_base)});

    try arch.late_init();

    try uacpi.event.install_fixed_event_handler(.power_button, &power_button_handler, null);
    try uacpi.event.finalize_gpe_initialization();

    try @import("objects/ob.zig").init(gpa);
    try @import("io/io.zig").init(gpa);

    const current_apic_id = hal.apic.get_lapic_id();

    log.info("local apic id {d}", .{current_apic_id});

    if (ldr_info.framebuffer.base == .nul) {
        log.warn("graphics-mode framebuffer not found by bootelf", .{});
        return error.no_framebuffer;
    }

    log.info("graphics-mode framebuffer located at 0x{X:0>16}..{X:0>16}, {d}x{d}, hblank {d}", .{
        @intFromEnum(ldr_info.framebuffer.base) + @as(usize, @bitCast(arch.pmm.phys_mapping_base)),
        @intFromEnum(ldr_info.framebuffer.base) + @as(usize, @bitCast(arch.pmm.phys_mapping_base)) + ldr_info.framebuffer.pitch * ldr_info.framebuffer.height,
        ldr_info.framebuffer.width,
        ldr_info.framebuffer.height,
        (ldr_info.framebuffer.pitch - ldr_info.framebuffer.width) / 4,
    });
    fb.init(&ldr_info.framebuffer);

    const f = @import("psf.zig").font;

    log.info("have a {d}x{d} font", .{ f.header.width, f.header.height });

    font_rendering.init();
    font_rendering.write("This is a test!\n=-+asbasdedfgwrgrgsae");
    log.info("wrote to screen", .{});

    // log.debug("__isrs[0]: {*}: {*}", .{ &arch.x86_64.idt.__isrs[0], arch.x86_64.idt.__isrs[0] });

    // log.debug("ap_trampoline: {*}", .{arch.x86_64.smp.ap_trampoline});

    const ext = util.extern_address;

    const ap_trampoline_length = ext("__ap_trampoline_end__") - ext("__ap_trampoline_begin__");
    const ap_trampoline_start = @as([*]const u8, @ptrFromInt(ext("__ap_trampoline_begin__")));

    log.debug("ap_trampoline: {*} (len {X})", .{ ap_trampoline_start, ap_trampoline_length });

    // try debug.dump_hex(ap_trampoline_start[0..ap_trampoline_length]);
    // debug.dump_stack_trace(log, null);

    // log.info("{}", .{@import("builtin").target});

    puts("STOP");
    while (true) {
        asm volatile ("hlt");
    }
}

fn power_button_handler(_: ?*anyopaque) callconv(arch.cc) uacpi.InterruptRet {
    log.info("ACPI POWER BUTTON PRESSED", .{});
    return .handled;
}

test {
    _ = @import("dispatcher/dispatcher.zig");
}
