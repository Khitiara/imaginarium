pub const SegmentType = enum(u1) {
    data = 0,
    code = 1,
};

pub const PackedSegmentFlags = packed union {
    data: packed struct(u3) {
        accessed: bool,
        writable: bool,
        expand_down: bool,
    },
    code: packed struct(u3) {
        accessed: bool,
        readable: bool,
        conforming: bool,
    },
};

pub const SegmentTypeField = packed struct(u4) {
    flags: PackedSegmentFlags,
    type: SegmentType,
};

test {
    _ = SegmentTypeField;
}