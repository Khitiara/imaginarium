const std = @import("std");

const bootelf = @import("bootelf.zig");
const types = @import("types.zig");

const hal = @import("hal");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;

// extern var fb: u0;

var current_apic_id: u8 = undefined;

export fn _start(ldr_info: *bootelf.BootelfData) callconv(.SysV) noreturn {
    // const ldr_info = asm("" : [ldr_info]"={rdi}"(-> *bootelf.BootelfData) ::);
    for (std.mem.toBytes(@intFromPtr(&ldr_info))) |b| {
        arch.x86_64.serial.outb(0xE9, .data, b);
    }
    main(ldr_info) catch {
        @trap();
    };
    while (true) {}
}

fn main(ldr_info: *bootelf.BootelfData) !void {
    std.debug.assert(ldr_info.magic == bootelf.magic);

    current_apic_id = (try cpuid.cpuid(.type_fam_model_stepping_features, 0)).brand_flush_count_id.apic_id;

    var buf = [1]u8{0} ** 64;
    const slice = try std.fmt.bufPrintZ(&buf, "{x}", .{current_apic_id});
    try arch.x86_64.serial.init_serial(0x3F8);
    for (slice) |value| {
        arch.x86_64.serial.writeout(0x3F8, value);
    }
}
