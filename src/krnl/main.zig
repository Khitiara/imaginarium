const std = @import("std");

const bootelf = @import("bootelf.zig");

const hal = @import("hal");
const util = @import("util");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;
const puts = arch.puts;

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

// // extern var fb: u0;
//
// // extern const _bootstrap_stack: [*]u8;
// // extern const _bootstrap_stack_length: usize;
// //
// // const bootstrap_stack: []u8 = _bootstrap_stack[0.._bootstrap_stack_length];
//
// const _bootstrap_stack_top = @extern(*anyopaque, .{ .name = "_bootstrap_stack_top" });
// const _bootstrap_stack_bottom = @extern(*anyopaque, .{ .name = "_bootstrap_stack_bottom" });

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
    arch.x86_64.serial.writeout(0xE9, 0);
    while (true) {
        asm volatile ("hlt");
    }
}

const hexblob: *const [16:0]u8 = "0123456789ABCDEF";

fn print_hex(num: u64) void {
    puts("0x");
    var i = num;
    for (0..3) |_| {
        for (0..4) |_| {
            arch.x86_64.serial.writeout(0xE9, hexblob[i & 0xF]);
            i /= 16;
        }
        arch.x86_64.serial.writeout(0xE9, '_');
    }
    for (0..4) |_| {
        arch.x86_64.serial.writeout(0xE9, hexblob[i & 0xF]);
        i /= 16;
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
    if (format.len == 0 or format[format.len - 1] != '\n')
        puts("\n");
}

pub const std_options: std.Options = .{
    .logFn = logFn,
};

const log = std.log.default;

noinline fn main(ldr_info: *bootelf.BootelfData) !void {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    try arch.platform_init(ldr_info.memory_map());

    const current_apic_id = (cpuid.cpuid(.type_fam_model_stepping_features, 0)).brand_flush_count_id.apic_id;

    log.info("local apic id {d}\n", .{current_apic_id});
    log.info("acpi oem id {s}\n", .{&arch.x86_64.oem_id});

    const paging_feats = arch.x86_64.paging.enumerate_paging_features();
    log.info("physical addr width: {d} (0x{x} pages)\n", .{ paging_feats.maxphyaddr, @as(u64, 1) << @truncate(paging_feats.maxphyaddr - 12) });
    log.info("linear addr width: {d}\n", .{paging_feats.linear_address_width});
    log.info("1g pages: {}; global pages: {}; lvl5 paging: {}\n", .{ paging_feats.gigabyte_pages, paging_feats.global_page_support, paging_feats.five_level_paging });

    var max_usable_physaddr: usize = 0;
    for (ldr_info.memory_map()) |entry| {
        const end = entry.base + entry.size;
        log.info("memmap 0x{X:0>12}..0x{X:0>12} (0x{X:0>10}) is {s: <10} ({x})\n", .{ entry.base, end, entry.size, @tagName(entry.type), @intFromEnum(entry.type) });
        if (entry.type == .normal and max_usable_physaddr < end) {
            max_usable_physaddr = end;
        }
    }
    log.info("max usable physaddr: 0x{X:0>12}\n", .{max_usable_physaddr});
    const max_usable_phys_page = max_usable_physaddr / 4096;
    log.info("max usable physical page: 0x{X:0>8}\n", .{max_usable_phys_page});
    const pagecntbytes = max_usable_phys_page / 8;
    const physpage_bitmap_len_pages = pagecntbytes / 4096;
    log.info("page bitmap length: 0x{X:0>8} bytes, 0x{X:0>4} pages\n", .{ pagecntbytes, physpage_bitmap_len_pages });
}
