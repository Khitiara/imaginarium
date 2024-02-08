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
