pub const Gas = extern struct {
    address_space: enum(u8) {
        system_memory = 0x0,
        system_io = 0x1,
        pci_config_space = 0x2,
        embedded_controller = 0x3,
        smbus = 0x4,
        cmos = 0x5,
        pci_bar_target = 0x6,
        ipmi = 0x7,
        gpio = 0x8,
        generic_serial = 0x9,
        pcc = 0xA,
        prm = 0xB,
        functional_fixed_hardware = 0x7F,
        _,
    },
    register_bit_width: u8,
    register_bit_offset: u8,
    access_size: enum(u8) {
        undefined = 0,
        byte = 1,
        word = 2,
        dword = 3,
        qword = 4,
        _,
    },
    address: packed union {
        system_memory: u64,
        system_io: u64,
        // pci_config_space
        // embedded_controller
        // smbus
        // cmos
        // pci_bar_target
        // ipmi
        // gpio
        // generic_serial
        // pcc
        // prm
        // functional_fixed_hardware
    } align(4),
};
