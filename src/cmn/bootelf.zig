const types = @import("types.zig");
const memmap = @import("memmap.zig");

pub const FramebufferInfo = extern struct {
    base: types.PhysAddr,
    pitch: u32,
    width: u32,
    height: u32,
};

pub const BootelfData = extern struct {
    magic: u64,
    entry_count: u64,
    entries: [*]memmap.Entry,
    framebuffer: FramebufferInfo,

    pub fn memory_map(self: *BootelfData) []memmap.Entry {
        return self.entries[0..self.entry_count];
    }
};

pub const magic: u64 = 0xB007E1F;
