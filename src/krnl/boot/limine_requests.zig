const limine = @import("limine.zig");

pub export var framebuffer_request: limine.FramebufferRequest linksection(".limine.fb") = .{};
pub export var memmap_request: limine.MemoryMapRequest linksection(".limine.mm") = .{};
pub export var rsdp_request: limine.RsdpRequest linksection(".limine.rsdp") = .{};
pub export var krnl_addr_request: limine.KernelAddressRequest linksection(".limine.krnl_addr") = .{};
pub export var hhdm_request: limine.HhdmRequest linksection(".limine.hhdm") = .{};
pub export var paging_mode_req: limine.PagingModeRequest linksection(".limine.paging") = .{
    .revision = 1,
    .mode = .four_level,
    .max_mode = .four_level,
    .min_mode = .four_level,
};

// pub export var krnl_file_request: limine.KernelFileRequest linksection(".limine.krnl_file") = .{};
