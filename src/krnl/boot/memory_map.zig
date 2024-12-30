const Pfi = @import("../hal/mm/pfmdb.zig").Pfi;

pub const MemoryKind = enum {
    usable,
    reserved,
    acpi_reclaimable,
    acpi_nvs,
    bad_memory,
    bootloader_reclaimable,
    loaded_image,
    framebuffer,
    persistent,
    disabled,
};

pub const MemoryDescriptor = struct {
    base_page: Pfi,
    page_count: Pfi,
    memory_kind: MemoryKind,
};