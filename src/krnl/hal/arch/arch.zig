pub const cpuid = @import("cpuid.zig");
pub const msr = @import("msr.zig");
pub const segmentation = @import("segmentation.zig");
pub const paging = @import("paging.zig");
pub const control_registers = @import("ctrl_registers.zig");
pub const serial = @import("serial.zig");
pub const descriptors = @import("descriptors.zig");
pub const gdt = @import("gdt.zig");
pub const pmm = @import("pmm.zig");
pub const vmm = @import("vmm.zig");
pub const idt = @import("idt.zig");
pub const interrupts = @import("interrupts.zig");
pub const rand = @import("rand.zig");
pub const smp = @import("smp.zig");
pub const time = @import("time.zig");
const std = @import("std");
const cmn = @import("cmn");
const types = cmn.types;

const acpi = @import("../acpi/acpi.zig");

pub const cc: @import("std").builtin.CallingConvention = types.cc;

pub fn puts(bytes: []const u8) void {
    for (bytes) |b| {
        serial.out(0xE9, b);
    }
}

pub const SerialWriter = struct {
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

pub fn delay_unsafe(cycles: u64) void {
    const target = time.rdtsc() + cycles;
    while (time.rdtsc() < target) {
        std.atomic.spinLoopHint();
    }
}

const log = std.log.scoped(.init);

pub const ptr_from_physaddr = pmm.ptr_from_physaddr;
pub const physaddr_from_ptr = pmm.physaddr_from_ptr;
const apic = @import("../apic/apic.zig");

pub fn platform_init(memmap: []cmn.memmap.Entry) !void {
    log.info("setting up GDT", .{});
    gdt.setup_gdt();
    log.info("gdt setup and loaded", .{});
    const paging_feats = paging.enumerate_paging_features();
    log.info("physical addr width: {d} (0x{x} pages)", .{ paging_feats.maxphyaddr, @as(u64, 1) << @truncate(paging_feats.maxphyaddr - 12) });
    log.info("linear addr width: {d}", .{paging_feats.linear_address_width});
    log.info("1g pages: {}; global pages: {}; lvl5 paging: {}", .{ paging_feats.gigabyte_pages, paging_feats.global_page_support, paging_feats.five_level_paging });
    pmm.init(paging_feats.maxphyaddr, memmap);
    log.info("initialized lower phys memory", .{});
    interrupts.init();
    log.info("interrupt table initialized", .{});
    try vmm.init(memmap);
    log.info("vmm initialized", .{});
    idt.load();
    log.info("interrupt table loaded", .{});
    var cr4 = control_registers.read(.cr4);
    cr4.osfxsr = true;
    control_registers.write(.cr4, cr4);
    idt.enable();
    log.info("interrupts enabled", .{});
    try @import("../acpi/zuacpi.zig").init();
    log.info("loaded acpi sdt", .{});
    apic.init();
    log.info("checked for x2apic compat and enabled apic in {s} mode", .{if (apic.x2apic.x2apic_enabled) "x2apic" else "xapic"});
    apic.bspid = apic.get_lapic_id();
    time.init_timing();
    log.info("timekeeping initialized", .{});
    log.info("early platform init complete", .{});
}

comptime {
    _ = @import("init.zig");
    _ = idt;
}

pub const Flags = types.Flags;

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

pub const SavedRegisterState = idt.InterruptFrame(u64);

pub const acpi_types = struct {
    pub const MsiAddressRegister = packed struct(u32) {
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
    };
    pub const MsiDataRegister = packed struct(u64) {
        vector: u8,
        delivery_mode: apic.DeliveryMode,
        _1: u3 = 0,
        assert: bool,
        trigger_mode: apic.TriggerMode,
        _2: u48 = 0,
    };
};

test {
    @import("std").testing.refAllDecls(@This());
}
