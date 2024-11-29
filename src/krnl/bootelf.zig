const hal = @import("hal/hal.zig");

pub const FramebufferInfo = extern struct {
    base: hal.arch.PhysAddr,
    pitch: u32,
    width: u32,
    height: u32,
};

pub const BootelfData = extern struct {
    magic: u64,
    entry_count: u64,
    entries: [*]hal.memory.MemoryMapEntry,
    framebuffer: FramebufferInfo,

    pub fn memory_map(self: *BootelfData) []hal.memory.MemoryMapEntry {
        return self.entries[0..self.entry_count];
    }
};

pub const magic: u64 = 0xB007E1F;
