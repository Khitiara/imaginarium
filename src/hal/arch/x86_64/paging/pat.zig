pub const PATMemoryType = enum(u3) {
    uncacheable = 0,
    write_combining = 1,
    write_through = 4,
    write_protected = 5,
    write_back = 6,
    uncached = 7,
    _,
};

pub const PATEntry = packed struct(u8) {
    memory_type: PATMemoryType,
    _: u5 = 0,
};

pub const PAT = [8]PATEntry;