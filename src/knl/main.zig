const std = @import("std");

const bootboot_utils = @import("bootboot.zig");
const BootBoot = bootboot_utils.BootBoot;

const hal = @import("hal");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;

extern var mmio: u0;

extern var bootboot: BootBoot;
extern var environment: [4096]u8;
extern var fb: [8]u32;

var current_apic_id: u8 = undefined;

export fn _start() callconv(.C) noreturn {
    main() catch @panic("!");
    while (true) {}
}

fn main() !void {
    std.debug.assert(std.mem.eql(u8, &bootboot.magic, bootboot_utils.bootboot_magic));

    current_apic_id = cpuid.cpuid(.type_fam_model_stepping_features, 0).brand_flush_count_id.apic_id;

    if (current_apic_id != bootboot.bspid) {
        try main_secondary_cpu();
    } else {
        try main_bootstrap();
    }
}

fn main_secondary_cpu() !void {}

fn main_bootstrap() !void {}
