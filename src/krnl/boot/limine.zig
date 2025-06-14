// Copyright (C) 2022-2024 48cf <iretq@riseup.net> and contributors.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

const std = @import("std");
const builtin = @import("builtin");

inline fn magic(a: u64, b: u64) [4]u64 {
    return .{ 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, a, b };
}

pub const LimineArch = enum {
    x86_64,
    aarch64,
    riscv64,
};

pub const arch = switch (builtin.cpu.arch) {
    .x86, .x86_64 => LimineArch.x86_64,
    .aarch64 => LimineArch.aarch64,
    .riscv64 => LimineArch.riscv64,
    else => @compileError("Unsupported architecture: " ++ @tagName(builtin.cpu.arch)),
};

pub const BaseRevision = extern struct {
    id: [2]u64 = .{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc },
    revision: u64,

    pub fn is_supported(self: *const volatile @This()) bool {
        return self.revision == 0;
    }
};

pub const Uuid = extern struct {
    a: u32,
    b: u16,
    c: u16,
    d: [8]u8,
};

pub const MediaType = enum(u32) {
    generic = 0,
    optical = 1,
    tftp = 2,
};

pub const File = extern struct {
    revision: u64,
    address: [*]u8,
    size: u64,
    path: [*:0]u8,
    string: [*:0]u8,
    media_type: MediaType,
    unused: u32,
    tftp_ip: u32,
    tftp_port: u32,
    partition_index: u32,
    mbr_disk_id: u32,
    gpt_disk_uuid: Uuid,
    gpt_part_uuid: Uuid,
    part_uuid: Uuid,

    pub inline fn data(self: *@This()) []u8 {
        return self.address[0..self.size];
    }
};

// Boot info

pub const BootloaderInfoResponse = extern struct {
    revision: u64,
    name: [*:0]u8,
    version: [*:0]u8,
};

pub const BootloaderInfoRequest = extern struct {
    id: [4]u64 = magic(0xf55038d8e2a1202f, 0x279426fcf5f59740),
    revision: u64 = 0,
    response: ?*BootloaderInfoResponse = null,
};

// Stack size

pub const StackSizeResponse = extern struct {
    revision: u64,
};

pub const StackSizeRequest = extern struct {
    id: [4]u64 = magic(0x224ef0460a8e8926, 0xe1cb0fc25f46ea3d),
    revision: u64 = 0,
    response: ?*StackSizeResponse = null,
    stack_size: u64,
};

// HHDM

pub const HhdmResponse = extern struct {
    revision: u64,
    offset: u64,
};

pub const HhdmRequest = extern struct {
    id: [4]u64 = magic(0x48dcf1cb8ad2b852, 0x63984e959a98244b),
    revision: u64 = 0,
    response: ?*HhdmResponse = null,
};

// Framebuffer

pub const FramebufferMemoryModel = enum(u8) {
    rgb = 1,
    _,
};

pub const VideoMode = extern struct {
    pitch: u64,
    width: u64,
    height: u64,
    bpp: u16,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
};

pub const Framebuffer = extern struct {
    address: [*]u8,
    width: u64,
    height: u64,
    pitch: u64,
    bpp: u16,
    memory_model: FramebufferMemoryModel,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
    unused: [7]u8,
    edid_size: u64,
    edid: ?[*]u8,

    // Response revision 1
    mode_count: u64,
    modes: [*]*VideoMode,

    pub inline fn data(self: *@This()) []u8 {
        return self.address[0 .. self.pitch * self.height];
    }

    pub inline fn edidData(self: *@This()) ?[]u8 {
        if (self.edid) |edid_data| {
            return edid_data[0..self.edid_size];
        }
        return null;
    }

    pub inline fn videoModes(self: *@This()) []*VideoMode {
        return self.modes[0..self.mode_count];
    }
};

pub const FramebufferResponse = extern struct {
    revision: u64,
    framebuffer_count: u64,
    framebuffers_ptr: [*]*Framebuffer,

    pub inline fn framebuffers(self: *@This()) []*Framebuffer {
        return self.framebuffers_ptr[0..self.framebuffer_count];
    }
};

pub const FramebufferRequest = extern struct {
    id: [4]u64 = magic(0x9d5827dcd881dd75, 0xa3148604f6fab11b),
    revision: u64 = 1,
    response: ?*FramebufferResponse = null,
};

// Paging mode

const X86PagingMode = enum(u64) {
    four_level = 0,
    five_level = 1,
};

const AArch64PagingMode = enum(u64) {
    four_level = 0,
    five_level = 1,
};

const RiscVPagingMode = enum(u64) {
    sv39 = 0,
    sv48 = 1,
    sv57 = 2,
};

pub const PagingMode = switch (arch) {
    .x86_64 => X86PagingMode,
    .aarch64 => AArch64PagingMode,
    .riscv64 => RiscVPagingMode,
};

pub const default_paging_mode = switch (arch) {
    .x86_64 => X86PagingMode.four_level,
    .aarch64 => AArch64PagingMode.four_level,
    .riscv64 => RiscVPagingMode.sv48,
};

pub const PagingModeResponse = extern struct {
    revision: u64,
    mode: PagingMode,
    flags: u64,
};

pub const PagingModeRequest = extern struct {
    id: [4]u64 = magic(0x95c1a0edab0944cb, 0xa4e5cb3842f7488a),
    revision: u64 = 0,
    response: ?*PagingModeResponse = null,
    mode: PagingMode,
    max_mode: PagingMode,
    min_mode: PagingMode,
};

// SMP
const X86SmpInfo = extern struct {
    processor_id: u32,
    lapic_id: u32,
    reserved: u64,
    goto_address: ?*const fn (*@This()) callconv(.C) noreturn,
    extra_argument: u64,
};

const X86SmpFlags = packed struct(u32) {
    x2apic: bool,
    _: u31 = 0,
};

const X86SmpRequestFlags = packed struct(u64) {
    x2apic: bool = false,
    _: u63 = 0,
};

const X86SmpResponse = extern struct {
    revision: u64,
    flags: u32,
    bsp_lapic_id: u32,
    cpu_count: u64,
    cpus_ptr: [*]*X86SmpInfo,

    pub inline fn cpus(self: *@This()) []*X86SmpInfo {
        return self.cpus_ptr[0..self.cpu_count];
    }
};

const AArch64SmpInfo = extern struct {
    processor_id: u32,
    gic_iface_no: u32,
    mpidr: u64,
    reserved: u64,
    goto_address: ?*const fn (*@This()) callconv(.C) noreturn,
    extra_argument: u64,
};

const AArch64SmpFlags = enum(u32) {};

const AArch64SmpResponse = extern struct {
    revision: u64,
    flags: u32,
    bsp_mpidr: u64,
    cpu_count: u64,
    cpus_ptr: [*]*AArch64SmpInfo,

    pub inline fn cpus(self: *@This()) []*AArch64SmpInfo {
        return self.cpus_ptr[0..self.cpu_count];
    }
};

const RiscVSmpInfo = extern struct {
    processor_id: u32,
    hart_id: u32,
    reserved: u64,
    goto_address: ?*const fn (*@This()) callconv(.C) noreturn,
    extra_argument: u64,
};

const RiscVSmpFlags = enum(u32) {};

const RiscVSmpResponse = extern struct {
    revision: u64,
    flags: u32,
    bsp_hart_id: u64,
    cpu_count: u64,
    cpus_ptr: [*]*RiscVSmpInfo,

    pub inline fn cpus(self: *@This()) []*RiscVSmpInfo {
        return self.cpus_ptr[0..self.cpu_count];
    }
};

pub const SmpInfo = switch (arch) {
    .x86_64 => X86SmpInfo,
    .aarch64 => AArch64SmpInfo,
    .riscv64 => RiscVSmpInfo,
};

pub const SmpFlags = switch (arch) {
    .x86_64 => X86SmpFlags,
    .aarch64 => AArch64SmpFlags,
    .riscv64 => RiscVSmpFlags,
};

pub const SmpRequestFlags = switch (arch) {
    .x86_64 => X86SmpRequestFlags,
    .aarch64 => u64,
    .riscv64 => u64,
};

pub const SmpResponse = switch (arch) {
    .x86_64 => X86SmpResponse,
    .aarch64 => AArch64SmpResponse,
    .riscv64 => RiscVSmpResponse,
};

pub const SmpRequest = extern struct {
    id: [4]u64 = magic(0x95a67b819a1b857e, 0xa0b61b723b6a73e0),
    revision: u64 = 0,
    response: ?*SmpResponse = null,
    flags: SmpRequestFlags = .{},
};

// Memory map

pub const MemoryMapEntryType = enum(u64) {
    usable = 0,
    reserved = 1,
    acpi_reclaimable = 2,
    acpi_nvs = 3,
    bad_memory = 4,
    bootloader_reclaimable = 5,
    loaded_image = 6,
    framebuffer = 7,
};

pub const MemoryMapEntry = extern struct {
    base: u64,
    length: u64,
    kind: MemoryMapEntryType,
};

pub const MemoryMapResponse = extern struct {
    revision: u64,
    entry_count: u64,
    entries_ptr: [*]*MemoryMapEntry,

    pub inline fn entries(self: *@This()) []*MemoryMapEntry {
        return self.entries_ptr[0..self.entry_count];
    }
};

pub const MemoryMapRequest = extern struct {
    id: [4]u64 = magic(0x67cf3d9d378a806f, 0xe304acdfc50c3c62),
    revision: u64 = 0,
    response: ?*MemoryMapResponse = null,
};

// Entry point

pub const EntryPointResponse = extern struct {
    revision: u64,
};

pub const EntryPointRequest = extern struct {
    id: [4]u64 = magic(0x13d86c035a1cd3e1, 0x2b0caa89d8f3026a),
    revision: u64 = 0,
    response: ?*EntryPointResponse = null,
    entry: ?*const fn () callconv(.C) noreturn = null,
};

// Kernel file

pub const KernelFileResponse = extern struct {
    revision: u64,
    kernel_file: *File,
};

pub const KernelFileRequest = extern struct {
    id: [4]u64 = magic(0xad97e90e83f1ed67, 0x31eb5d1c5ff23b69),
    revision: u64 = 0,
    response: ?*KernelFileResponse = null,
};

// Module

pub const InternalModuleFlags = packed struct(u64) {
    required: bool,
    _: u63 = 0,
};

pub const InternalModule = extern struct {
    path: [*:0]const u8,
    string: [*:0]const u8,
    flags: InternalModuleFlags,
};

pub const ModuleResponse = extern struct {
    revision: u64,
    module_count: u64,
    modules_ptr: [*]*File,

    pub inline fn modules(self: *@This()) []*File {
        return self.modules_ptr[0..self.module_count];
    }
};

pub const ModuleRequest = extern struct {
    id: [4]u64 = magic(0x3e7e279702be32af, 0xca1c4f3bd1280cee),
    revision: u64 = 1,
    response: ?*ModuleResponse = null,

    // Request revision 1
    internal_modules_count: u64 = 0,
    internal_modules: ?[*]const *const InternalModule = null,
};

// RSDP

pub const RsdpResponse = extern struct {
    revision: u64,
    address: @import("cmn").types.PhysAddr,
};

pub const RsdpRequest = extern struct {
    id: [4]u64 = magic(0xc5e77b6b397e7b43, 0x27637845accdcf3c),
    revision: u64 = 0,
    response: ?*RsdpResponse = null,
};

// SMBIOS

pub const SmbiosResponse = extern struct {
    revision: u64,
    entry_32: ?*anyopaque,
    entry_64: ?*anyopaque,
};

pub const SmbiosRequest = extern struct {
    id: [4]u64 = magic(0x9e9046f11e095391, 0xaa4a520fefbde5ee),
    revision: u64 = 0,
    response: ?*SmbiosResponse = null,
};

// EFI system table

pub const EfiSystemTableResponse = extern struct {
    revision: u64,
    address: *const std.os.uefi.tables.SystemTable,
};

pub const EfiSystemTableRequest = extern struct {
    id: [4]u64 = magic(0x5ceba5163eaaf6d6, 0x0a6981610cf65fcc),
    revision: u64 = 0,
    response: ?*EfiSystemTableResponse = null,
};

// EFI memory map

pub const EfiMemoryMapResponse = extern struct {
    revision: u64,
    memmap: *anyopaque,
    memmap_size: u64,
    desc_size: u64,
    desc_version: u64,
};

pub const EfiMemoryMapRequest = extern struct {
    id: [4]u64 = magic(0x7df62a431d6872d5, 0xa4fcdfb3e57306c8),
    revision: u64 = 0,
    response: ?*EfiMemoryMapResponse = null,
};

// Boot time

pub const BootTimeResponse = extern struct {
    revision: u64,
    boot_time: i64,
};

pub const BootTimeRequest = extern struct {
    id: [4]u64 = magic(0x502746e184c088aa, 0xfbc5ec83e6327893),
    revision: u64 = 0,
    response: ?*BootTimeResponse = null,
};

// Kernel address

pub const KernelAddressResponse = extern struct {
    revision: u64,
    physical_base: u64,
    virtual_base: u64,
};

pub const KernelAddressRequest = extern struct {
    id: [4]u64 = magic(0x71ba76863cc55f63, 0xb2644a48c516a487),
    revision: u64 = 0,
    response: ?*KernelAddressResponse = null,
};

// Device tree blob

pub const DeviceTreeBlobResponse = extern struct {
    revision: u64,
    dtb: ?*anyopaque,
};

pub const DeviceTreeBlobRequest = extern struct {
    id: [4]u64 = magic(0xb40ddb48fb54bac7, 0x545081493f81ffb7),
    revision: u64 = 0,
    response: ?*DeviceTreeBlobResponse = null,
};

pub const FirmwareType =enum(u64) {
    x86_bios = 0,
    uefi32 = 1,
    uefi64 = 2,
    sbi = 3,
    _
};

pub const FirmwareTypeResponse = extern struct {
    revision: u64,
    firmware_type: FirmwareType,
};

pub const FirmwareTypeRequest = extern struct {
        id: [4]u64 = magic(0x8c2f75d90bef28a8, 0x7045a4688eac00c3 ),
    revision: u64 = 0,
    response: ?*FirmwareTypeResponse = null,
};