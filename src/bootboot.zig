pub const bootboot_magic = "BOOT";

// default virtual addresses for level 0 and 1 static loaders
pub const bootboot_mmio = 0xfffffffff8000000; // memory mapped IO virtual address
pub const bootboot_fb = 0xfffffffffc000000; // frame buffer virtual address
pub const bootboot_info = 0xffffffffffe00000; // bootboot struct virtual address
pub const bootboot_env = 0xffffffffffe01000; // environment string virtual address
pub const bootboot_core = 0xffffffffffe02000; // core loadable segment start

// framebuffer pixel format, only 32 bits supported
pub const FramebufferFormat = enum(u8) {
    argb = 0,
    rgba = 1,
    abgr = 2,
    bgra = 3,
};

pub const ProtocolLevel = enum(u2) {
    minimal = 0,
    static = 1,
    dynamic = 2,
};

pub const Loader = enum(u2) {
    bios = 0,
    uefi = 1,
    rpi = 2,
    coreboot = 3,
};

pub const Protocol = packed struct(u8) {
    level: ProtocolLevel,
    loader: Loader,
    _: u3,
    bigendian: bool,
};

// mmap entry, type is stored in least significant tetrad (half byte) of size
// this means size described in 16 byte units (not a problem, most modern
// firmware report memory in pages, 4096 byte units anyway).
pub const MemoryMapEntry = extern struct {
    ptr: [*]u8,
    size_and_type: packed struct(u64) {
        type: u4,
        size: u60,
    },

    const Self = @This();

    pub inline fn getSizeInBytes(self: *const Self) u64 {
        return self.size_and_type.size << 4;
    }

    pub inline fn getSizeInPages(self: *const Self) u64 {
        return self.getSizeInBytes() / 4096;
    }

    pub inline fn isFree(self: *const Self) bool {
        return self.size_and_type.type == .free;
    }

    pub inline fn slice(self: *const Self) []u8 {
        return self.ptr[0..self.getSizeInBytes()];
    }
};

pub const MemoryMapType = enum(u4) {
    /// don't use. Reserved or unknown regions
    used = 0,

    /// usable memory
    free = 1,

    /// acpi memory, volatile and non-volatile as well
    acpi = 2,

    /// memory mapped IO region
    mmio = 3,
};

pub const initrd_max_size = 16; // Mb

const builtin = @import("builtin");

pub const BootBoot = extern struct {
    magic: [4]u8 align(1),
    size: u32 align(1),
    protocol: Protocol align(1),
    fb_type: FramebufferFormat align(1),
    numcores: u16 align(1),
    bspid: u16 align(1),
    timezone: i16 align(1),
    datetime: [8]u8 align(1),
    initrd_ptr: [*]u8 align(1),
    initrd_size: u64 align(1),
    fb_ptr: [*]u32 align(1),
    fb_size: u32 align(1),
    fb_width: u32 align(1),
    fb_height: u32 align(1),
    fb_scanline: u32 align(1),

    arch: switch (builtin.cpu.arch) {
        .x86_64 => extern struct {
            acpi_ptr: [*]u8,
            smbi_ptr: [*]u8,
            efi_ptr: [*]u8,
            mp_ptr: [*]u8,
            _: [4]u64,
        },
        .aarch64 => extern struct {
            acpi_ptr: [*]u8,
            mmio_ptr: [*]u8,
            efi_ptr: [*]u8,
            _: [5]u64,
        },
        else => |a| @compileError("Arch " ++ @tagName(a) ++ " is not supported by the bootloader"),
    } align(1),

    pub inline fn get_mmap(self: *BootBoot) []MemoryMapEntry {
        return @as([*]u8, @ptrCast(self))[@sizeOf(BootBoot)..self.size];
    }

    pub inline fn get_initrd(self: *BootBoot) []u8 {
        return self.initrd_ptr[0..self.initrd_size];
    }

    pub inline fn get_fb(self: *BootBoot) []u32 {
        return self.fb_ptr[0..self.fb_size];
    }
};

fn toString(comptime x: comptime_int) []const u8 {
    const std = @import("std");
    var mem = std.mem.zeroes([1000]u8);
    return std.fmt.bufPrint(&mem, "{}", .{x}) catch unreachable;
}

comptime {
    if (@sizeOf(@TypeOf(@as(BootBoot, undefined).arch)) != 64) {
        @compileError("Bootboot arch struct alignment is wrong, got " ++ toString(@sizeOf(@TypeOf(@as(BootBoot, undefined).arch))));
    }
}
