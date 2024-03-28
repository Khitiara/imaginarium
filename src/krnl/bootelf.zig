const types = @import("types.zig");

pub const RegionType = enum(u32) {
    normal = 1,
    reserved,
    acpi_reclaimable,
    acpi_nvs,
    unusable,
    disabled,
    persistent_memory,
    _,
};

pub const ExtendedAddressRangeAttributes = packed struct(u32) {
    _reserved1: u1 = 1,
    _reserved2: u2 = 0,
    address_range_error_log: bool,
    _reserved3: u28 = 0,
};

pub const MemoryMapEntry = extern struct {
    base: types.PhysicalAddress,
    size: usize,
    type: RegionType,
    attributes: ExtendedAddressRangeAttributes,
};

pub const FramebufferInfo = extern struct {
    base: types.PhysicalAddress,
    pitch: u32,
    width: u32,
    height: u32,
};

pub const BootelfData = extern struct {
    magic: u64 = 0xB00731F,
    entry_count: u64,
    entries: [*]MemoryMapEntry,
    framebuffer: FramebufferInfo,

    pub fn memory_map(self: *BootelfData) []MemoryMapEntry {
        return self.entries[0..self.entry_count];
    }
};

pub const magic: u64 = 0xB007E1F;