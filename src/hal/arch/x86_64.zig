pub const cpuid = @import("x86_64/cpuid.zig");
pub const msr = @import("x86_64/msr.zig");
pub const segmentation = @import("x86_64/segmentation.zig");
pub const paging = @import("x86_64/paging.zig");
pub const control_registers = @import("x86_64/ctrl_registers.zig");
pub const serial = @import("x86_64/serial.zig");
pub const descriptors = @import("x86_64/descriptors.zig");
pub const gdt = @import("x86_64/gdt.zig");
pub const pmm = @import("x86_64/pmm.zig");
pub const vmm = @import("x86_64/vmm.zig");
pub const idt = @import("x86_64/idt.zig");
pub const interrupts = @import("x86_64/interrupts.zig");

const memory = @import("../memory.zig");
const acpi = @import("../acpi.zig");

pub const cc: @import("std").builtin.CallingConvention = .Win64;

pub fn puts(bytes: []const u8) void {
    for (bytes) |b| {
        serial.writeout(0xE9, b);
    }
}

const log = @import("std").log.scoped(.init);

pub const ptr_from_physaddr = pmm.ptr_from_physaddr;

pub var oem_id: [6]u8 = undefined;

pub fn platform_init(memmap: []memory.MemoryMapEntry) !void {
    log.info("setting up GDT", .{});
    gdt.setup_gdt();
    log.info("gdt setup and loaded", .{});
    const paging_feats = paging.enumerate_paging_features();
    log.info("physical addr width: {d} (0x{x} pages)", .{ paging_feats.maxphyaddr, @as(u64, 1) << @truncate(paging_feats.maxphyaddr - 12) });
    log.info("linear addr width: {d}", .{paging_feats.linear_address_width});
    log.info("1g pages: {}; global pages: {}; lvl5 paging: {}", .{ paging_feats.gigabyte_pages, paging_feats.global_page_support, paging_feats.five_level_paging });
    try acpi.load_sdt(&oem_id);
    log.info("loaded acpi sdt", .{});
    pmm.init(paging_feats.maxphyaddr, memmap);
    log.info("initialized lower phys memory", .{});
    interrupts.init();
    log.info("interrupt table initialized", .{});
    try vmm.init(memmap);
    log.info("vmm initialized", .{});
    idt.load();
    log.info("interrupt table loaded", .{});
    idt.enable();
    log.info("early platform init complete", .{});
}

comptime {
    _ = @import("x86_64/init.zig");
    _ = idt;
}

pub const Flags = packed struct(u64) {
    carry: bool,
    _reserved1: u1 = 1,
    parity: bool,
    _reserved2: u1 = 0,
    aux_carry: bool,
    _reserved3: u1 = 0,
    zero: bool,
    sign: bool,
    trap: bool,
    interrupt_enable: bool,
    direction: bool,
    overflow: bool,
    iopl: u2,
    nt: bool,
    mode: bool,
    res: bool,
    vm: bool,
    alignment_check: bool,
    vif: bool,
    vip: bool,
    cpuid: bool,
    _reserved4: u8 = 0,
    aes_keyschedule_loaded: bool,
    alternate_instruction_set: bool,
    _reserved5: u32 = 0,
};

pub fn flags() Flags {
    return asm volatile (
        \\pushfq
        \\pop %[flags]
        : [flags] "=r" (-> Flags),
    );
}

pub fn setflags(f: Flags) void {
    asm volatile (
        \\push %[flags]
        \\popfq
        :
        : [flags] "r" (f),
        : "flags"
    );
}

test {
    @import("std").testing.refAllDecls(@This());
}
