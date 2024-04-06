const std = @import("std");

const bootelf = @import("bootelf.zig");

const hal = @import("hal");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;

const SerialWriter = struct {
    const WriteError = error{};
    pub const Writer = std.io.GenericWriter(*const anyopaque, error{}, typeErasedWriteFn);

    var written: u5 = 0;

    fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) error{}!usize {
        _ = context;
        for (bytes) |b| {
            arch.x86_64.serial.writeout(0xE9, b);
            written +%= 1;
        }
        return bytes.len;
    }

    pub fn writer() Writer {
        return .{ .context = undefined };
    }

    pub fn write_null_and_pad() void {
        while (written != 31) {
            arch.x86_64.serial.writeout(0xE9, ' ');
            written +%= 1;
        }
        arch.x86_64.serial.writeout(0xE9, '\n');
        written +%= 1;
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
    arch.platform_init();
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
    for (0..32) |_| {
        arch.x86_64.serial.writeout(0xE9, '.');
        // print a bunch of .s so i can tell if we made it into the loop
    }
    while (true) {
        asm volatile ("hlt");
    }
}

noinline fn main(ldr_info: *bootelf.BootelfData) !void {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    const current_apic_id = (cpuid.cpuid(.type_fam_model_stepping_features, 0)).brand_flush_count_id.apic_id;

    const writer = SerialWriter.writer();
    _ = try writer.print("local apic id {x}", .{current_apic_id});
    SerialWriter.write_null_and_pad();

    var oem_id: [6]u8 = undefined;
    try acpi.load_sdt(&oem_id);
    _ = try writer.print("acpi oem id {s}", .{&oem_id});
    SerialWriter.write_null_and_pad();

    const paging_feats = arch.x86_64.paging.enumerate_paging_features();
    try writer.print("physical addr width {d}", .{paging_feats.maxphyaddr});
    SerialWriter.write_null_and_pad();
    try writer.print("linear addr width {d}", .{paging_feats.linear_address_width});
    SerialWriter.write_null_and_pad();
    try writer.print("1g pages: {}; global pages: {}; lvl5 paging: {}", .{ paging_feats.gigabyte_pages, paging_feats.global_page_support, paging_feats.five_level_paging });
    SerialWriter.write_null_and_pad();
}
