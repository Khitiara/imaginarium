pub const AcpiPerArchTypes = struct {
    MsiAddressRegister: type,
    MsiDataRegister: type,
};

const apic = @import("../apic/apic.zig");

pub usingnamespace switch (@import("builtin").cpu.arch) {
    .aarch64 => struct {
        pub const aarch64 = @import("aarch64/aarch64.zig");
        pub const cc = aarch64.cc;
        pub const platform_init = aarch64.platform_init;

        pub fn phys_mem_base() isize {
            return undefined;
        }
    },
    .x86_64 => struct {
        pub const x86_64 = @import("x86_64/x86_64.zig");
        pub const cc = x86_64.cc;
        pub const platform_init = x86_64.platform_init;
        pub const puts = x86_64.puts;
        pub const ptr_from_physaddr = x86_64.ptr_from_physaddr;

        pub const serial = x86_64.serial;

        pub const get_and_disable_interrupts = x86_64.idt.get_and_disable;
        pub const restore_interrupt_state = x86_64.idt.restore;
        pub const disable_interrupts = x86_64.idt.disable;
        pub const enable_interrupts = x86_64.idt.enable;

        pub const delay_unsafe = x86_64.delay_unsafe;

        pub const is_vector_free = x86_64.idt.is_vector_free;

        pub const smp = x86_64.smp;
        pub const SavedRegisterState = x86_64.idt.InterruptFrame(u64);

        pub fn phys_mem_base() isize {
            return x86_64.pmm.phys_mapping_base;
        }

        pub const acpi_types: AcpiPerArchTypes = .{
            .MsiAddressRegister = packed struct(u32) {
                _1: u2 = 0,
                dm: enum(u1) {
                    physical = 0,
                    logical = 1,
                    },
                rh: enum(u1) {
                    direct = 0,
                    indirect = 1,
                    },
                _2: u8 = 0,
                destination_id: u8,
                _3: u12 = 0xFEE,
                },
            .MsiDataRegister = packed struct(u64) {
                vector: u8,
                delivery_mode: apic.DeliveryMode,
                _1: u3 = 0,
                assert: bool,
                trigger_mode: apic.TriggerMode,
                _2: u48 = 0,
                },
        };
    },
    else => |arch| @compileError("Unsupported architecture " ++ @tagName(arch)),
};

test {
    @import("std").testing.refAllDecls(@This());
}
