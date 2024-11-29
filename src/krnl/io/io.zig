pub const Device = @import("Device.zig");
pub const Driver = @import("Driver.zig");

pub const GenericAddress = union(enum) {
    memory: usize,
    io_port: u16,
    pci_configuration: struct {
        segment_group: u16,
        bus: u8,
        device: u5,
        function: u3,
        offset: u10,
    },
    pci_bar_target: struct {
        segment: u8,
        bus: u8,
        device: u5,
        function: u3,
        bar: u3,
        offset: u36,
    },
};