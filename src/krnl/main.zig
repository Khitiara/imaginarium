const std = @import("std");

const bootelf = @import("bootelf.zig");
const types = @import("types.zig");

const hal = @import("hal");

const arch = hal.arch;
const cpuid = arch.x86_64.cpuid;

const acpi = hal.acpi;

const SerialWriter = struct {
    const WriteError = error{};
    pub const Writer = std.io.GenericWriter(*const anyopaque, error{}, typeErasedWriteFn);

    fn typeErasedWriteFn(context: *const anyopaque, bytes: []const u8) error{}!usize {
        _ = context;
        for (bytes) |b| {
            arch.x86_64.serial.writeout(0xE9, b);
        }
        return bytes.len;
    }

    pub fn writer() Writer {
        return .{ .context = undefined };
    }
};

// extern var fb: u0;

// extern const _bootstrap_stack: [*]u8;
// extern const _bootstrap_stack_length: usize;
//
// const bootstrap_stack: []u8 = _bootstrap_stack[0.._bootstrap_stack_length];

const _bootstrap_stack_top = @extern(*anyopaque, .{ .name = "_bootstrap_stack_top" });
const _bootstrap_stack_bottom = @extern(*anyopaque, .{ .name = "_bootstrap_stack_bottom" });

export fn _kstart() callconv(.Naked) noreturn {
    asm volatile (
        \\ movq %[_stack], %rsp
        \\ pushq $0
        \\ pushq $0
        \\ xorq %rbp, %rbp
        \\ call *%[_kstart2]
        :
        : [_kstart2] "r" (&_kstart2),
          [_stack] "N{dx}" (&_bootstrap_stack_top),
        : "rdi"
    );
}

fn _kstart2(ldr_info: *bootelf.BootelfData) callconv(.SysV) noreturn {
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
    while (true) {}
}

noinline fn main(ldr_info: *bootelf.BootelfData) !void {
    const bootelf_magic_check = ldr_info.magic == bootelf.magic;
    std.debug.assert(bootelf_magic_check);

    if (!cpuid.check_cpuid_supported())
        return error.cpuid_not_supported;
    const current_apic_id = (try cpuid.cpuid(.type_fam_model_stepping_features, 0)).brand_flush_count_id.apic_id;

    const writer = SerialWriter.writer();
    _ = try writer.print("local apic id {x}", .{current_apic_id});
    try writer.writeByte(0);
}
