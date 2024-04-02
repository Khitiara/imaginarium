const std = @import("std");

const bootelf = @import("bootelf.zig");
const types = @import("types.zig");

const hal = @import("hal");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;

// extern var fb: u0;

extern const _bootstrap_stack: [*]u8;
extern const _bootstrap_stack_length: usize;

const bootstrap_stack: []u8 = _bootstrap_stack[0.._bootstrap_stack_length];

var current_apic_id: u8 = undefined;

export fn _start(ldr_info: *bootelf.BootelfData) callconv(.SysV) noreturn {
    // const ldr_info = asm("" : [ldr_info]"={rdi}"(-> *bootelf.BootelfData) ::);
    // for (std.mem.toBytes(@intFromPtr(ldr_info))) |b| {
    //     arch.x86_64.serial.outb(0xE9, .data, b);
    // }
    main(ldr_info) catch {
        @trap();
    };
    while (true) {}
}

var printBuf: [64]u8 = undefined;

noinline fn main(ldr_info: *bootelf.BootelfData) !void {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    if (!cpuid.check_cpuid_supported())
        return error.cpuid_not_supported;
    current_apic_id = (try cpuid.cpuid(.type_fam_model_stepping_features, 0)).brand_flush_count_id.apic_id;

    const slice = try std.fmt.bufPrintZ(&printBuf, "{x}", .{current_apic_id});
    try arch.x86_64.serial.init_serial(0xE9);
    for (slice) |value| {
        arch.x86_64.serial.writeout(0xE9, value);
    }
}
