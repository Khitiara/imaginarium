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

const SerialWriter = struct {
    const WriteError = error{};
    pub const Writer = std.io.GenericWriter(*const anyopaque, error{}, typeErasedWriteFn);

    fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) error{}!usize {
        _ = context;
        puts(bytes);
        return bytes.len;
    }

    pub fn writer() Writer {
        return .{ .context = undefined };
    }
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
            },
        }
    };
    puts("STOP");
    while (true) {
        asm volatile ("hlt");
    }
}

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
    SerialWriter.writer().print(format, args) catch unreachable;
    if (format.len == 0 or format[format.len - 1] != '\n') {
        puts("\n");
    }
}

pub const std_options: std.Options = .{
    .logFn = logFn,
};

const log = std.log.default;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    log.err("PANIC {s}, IP={X:0>16}; error return trace:", .{ msg, ret_addr orelse 0 });
    if (error_return_trace) |stk| {
        var i: usize = 0;
        var frame_index: usize = 0;
        var frames_left: usize = @min(stk.index, stk.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % stk.instruction_addresses.len;
            i += 1;
        }) {
            const return_address = stk.instruction_addresses[frame_index];
            log.err("    {d: <4}: {x:0>16}", .{ i, return_address });
        }
    }
    log.err("current stack trace: ", .{});
    var addrs: [16]usize = undefined;
    var trace: std.builtin.StackTrace = .{
        .instruction_addresses = &addrs,
        .index = 0,
    };
    std.debug.captureStackTrace(ret_addr orelse @returnAddress(), &trace);
    {
        var i: usize = 0;
        var frame_index: usize = 0;
        var frames_left: usize = @min(trace.index, trace.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % trace.instruction_addresses.len;
            i += 1;
        }) {
            const return_address = trace.instruction_addresses[frame_index];
            log.err("    {d: <4}: {x:0>16}", .{ i, return_address });
        }
    }
    while (true) {
        @breakpoint();
    }
}

fn main(ldr_info: *bootelf.BootelfData) !void {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    try arch.platform_init(ldr_info.memory_map());

    const current_apic_id = (cpuid.cpuid(.type_fam_model_stepping_features, 0)).brand_flush_count_id.apic_id;

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
}
