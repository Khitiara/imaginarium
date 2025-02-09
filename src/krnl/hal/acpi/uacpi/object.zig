const uacpi = @import("uacpi.zig");

pub const ProcessorInfo = extern struct {
    id: u8,
    block_address: u32,
    block_length: u8,
};

extern fn uacpi_object_get_processor_info(object: *uacpi.Object, out: *ProcessorInfo) uacpi.uacpi_status;
pub fn get_processor_info(object: *uacpi.Object) !ProcessorInfo {
    var info: ProcessorInfo = undefined;
    try uacpi_object_get_processor_info(object, &info).err();
    return info;
}