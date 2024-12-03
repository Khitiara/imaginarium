const uacpi = @import("uacpi.zig");

pub const InterruptModel = enum(u32) {
    pic = 0,
    ioapic = 1,
    iosapic = 2,
};

extern fn uacpi_set_interrupt_model(InterruptModel) uacpi.uacpi_status;

pub fn set_interrupt_model(model: InterruptModel) !void {
    try uacpi_set_interrupt_model(model).err();
}
