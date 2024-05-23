const std = @import("std");

const bootelf = @import("bootelf.zig");

const hal = @import("hal");
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

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    puts(util.upper_string_comptime(message_level.asText()));
    if (scope != .default) {
        puts(" (");
        puts(util.lower_string_comptime(@tagName(scope)));
        puts(")");
    }
    puts(": ");
    debug.SerialWriter.writer().print(format, args) catch unreachable;
    if (format.len == 0 or format[format.len - 1] != '\n') {
        puts("\n");
    }
}

pub const os = struct {
    pub const heap = struct {
        pub const page_allocator = arch.x86_64.vmm.raw_page_allocator.allocator();
    };
    pub const panic = debug.panic;
};

pub const std_options: std.Options = .{
    .logFn = logFn,
    .log_level = .debug,
    // .crypto_always_getrandom = true,
    .cryptoRandomSeed = arch.x86_64.rand.fill_secure,
};

/// the true entry point is __kstart and is exported by global asm in `hal/arch/{arch}/init.zig`
/// __kstart is responsible for stack setup and jumps unconditionally into __kstart2
/// __kstart2 is responsible for calling main and handling any zig errors returned from there
/// as well as entering the final infinite loop if everything worked successfully
export fn __kstart2(ldr_info: *bootelf.BootelfData) callconv(arch.cc) noreturn {
    main(ldr_info) catch |e| {
        switch (e) {
            inline else => |e2| {
                const ename = @errorName(e2);
                for (ename) |c| {
                    arch.x86_64.serial.writeout(0xE9, c);
                }
                debug.print_stack_trace(log, @errorReturnTrace().?);
            },
        }
    };
    while (true) {
        asm volatile ("hlt");
    }
}

noinline fn main(ldr_info: *bootelf.BootelfData) !void {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    try arch.platform_init(ldr_info.memory_map());
    debug.dump_stack_trace(log, null);
    try arch.smp.init(smp.allocate_lcbs);

    const current_apic_id = cpuid.cpuid(.type_fam_model_stepping_features, {}).brand_flush_count_id.apic_id;

    log.info("local apic id {d}", .{current_apic_id});
    log.info("acpi oem id {s}", .{&arch.x86_64.oem_id});

    if (ldr_info.framebuffer.base == 0) {
        log.warn("graphics-mode framebuffer not found by bootelf", .{});
        return;
    }

    log.info("graphics-mode framebuffer located at 0x{X:0>16}..{X:0>16}, {d}x{d}, hblank {d}", .{
        ldr_info.framebuffer.base + @as(usize, @bitCast(arch.phys_mem_base())),
        ldr_info.framebuffer.base + @as(usize, @bitCast(arch.phys_mem_base())) + ldr_info.framebuffer.pitch * ldr_info.framebuffer.height,
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

    const ap_trampoline_length = ext("__ap_trampoline_end") - ext("__ap_trampoline_begin");
    const ap_trampoline_start = @as([*]const u8, @ptrFromInt(ext("__ap_trampoline_begin")));

    log.debug("ap_trampoline: {*} (len {X})", .{ ap_trampoline_start, ap_trampoline_length });

    try debug.dump_hex(ap_trampoline_start[0..ap_trampoline_length]);
    debug.dump_stack_trace(log, null);

    log.info("{}", .{@import("builtin").target});

    puts("STOP");
    while (true) {}
}

test {
    _ = @import("dispatcher/dispatcher.zig");
}
