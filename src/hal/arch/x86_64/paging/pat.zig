pub const PATMemoryType = enum(u3) {
    uncacheable = 0,
    write_combining = 1,
    write_through = 4,
    write_protected = 5,
    write_back = 6,
    uncached = 7,
    _,
};

pub const PAT = [8]PATMemoryType;