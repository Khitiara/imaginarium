pub const DeliveryMode = enum(u3) {
    fixed = 1,
    smi = 2,
    nmi = 4,
    init = 5,
    exint = 7,
    _,
};

pub const TimerMode = enum(u2) {
    one_shot,
    periodic,
    tsc_deadline,
    _,
};

pub const ErrorStatusRegister = packed struct(u32) {
    send_checksum: bool,
    recv_checksum: bool,
    send_accept: bool,
    recv_accept: bool,
    redirectable_ipi: bool,
    send_illegal_vector: bool,
    recvd_illegal_vector: bool,
    illegal_register_address: bool,
    _: u24,
};

pub const SpuriousInterrupt = packed struct(u32) {
    spurious_vector: u8,
    apic_software_enabled: bool,
    focus_processor_checking: bool,
    _reserved1: u2,
    suppress_eoi_bcasts: bool,
    _reserved2: u20,
};

pub const IcrHigh = packed struct(u32) {
    _: u24 = 0,
    dest: u8,
};

pub const IcrLow = packed struct(u32) {
    vector: u8,
    delivery: enum(u3) {
        fixed = 0,
        lowest = 1,
        smi = 2,
        nmi = 4,
        init = 5,
        startup = 6,
        _,
    },
    dest_mode: enum(u1) {
        physical = 0,
        logical = 1,
    },
    pending: bool,
    _1: u1 = 0,
    assert: bool,
    trigger_mode: enum(u1) {
        edge = 0,
        level = 1,
    },
    _2: u2 = 0,
    shorthand: packed struct(u2) {
        self: bool,
        all: bool,
    },
    _3: u12 = 0,
};
