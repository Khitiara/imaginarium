const limine_reqs = @import("limine_requests.zig");
const limine = @import("limine.zig");
const config = @import("config");
const cmn = @import("cmn");
const types = cmn.types;
const PhysAddr = types.PhysAddr;
const std = @import("std");
const util = @import("util");

pub const memory_map = @import("memory_map.zig");

pub fn hhdm_base() [*]align(4096) u8 {
    return @ptrFromInt(limine_reqs.hhdm_request.response.?.offset);
}

pub fn kernel_physaddr_base() PhysAddr {
    return limine_reqs.krnl_addr_request.response.?.physical_base;
}

const MemoryMapEntry: type = *limine.MemoryMapEntry;

const MemoryMap = []MemoryMapEntry;

pub var bootelf_data: *cmn.bootelf.BootelfData linksection(".init") = undefined;

fn get_raw_memory_map() MemoryMap {
    return limine_reqs.memmap_request.response.?.entries();
}

pub fn get_kernel_image_info() struct {
    kernel_phys_addr_base: usize,
    kernel_virt_addr_base: usize,
    kernel_len_pages: usize,
} {
    const size = @intFromPtr(@extern(*anyopaque, .{ .name = "__kernel_length__" }));
    const resp = limine_reqs.krnl_addr_request.response.?;
    return .{
        .kernel_phys_addr_base = resp.physical_base,
        .kernel_virt_addr_base = resp.virtual_base,
        .kernel_len_pages = @import("../hal/mm/mm.zig").pages_spanned(resp.virtual_base, size),
    };
}

pub const FramebufferMemoryModel = enum {
    rgb,
};

pub const VideoMode = struct {
    width: u64,
    height: u64,
    pitch: u64,
    bits_per_pixel: u16,
    model: FramebufferMemoryModel,
};

pub const Framebuffer = struct {
    phys_addr: PhysAddr,
    base: ?[*]u8,
    mode: VideoMode,
    edid: ?struct {
        size: u64,
        addr: PhysAddr,
    },
};

pub var memmap: []memory_map.MemoryDescriptor = undefined;
pub var framebuffers: []Framebuffer = undefined;
pub var rsdp_addr: PhysAddr = undefined;

pub var smp: limine.SmpResponse = undefined;
pub var cpus: []limine.SmpInfo = undefined;

var system_info_buffer: [2 * 4096]u8 = undefined;
var system_info_alloc: std.heap.FixedBufferAllocator = .init(&system_info_buffer);

pub noinline fn dupe_bootloader_data() !void {
    limine_reqs.fix_optimizations();
    const alloc = system_info_alloc.allocator();
    {
        const raw_mm = get_raw_memory_map();
        memmap = try alloc.alloc(memory_map.MemoryDescriptor, raw_mm.len);

        for (raw_mm, memmap) |e, *desc| {
            desc.memory_kind = switch (e.kind) {
                inline else => |kind| @field(memory_map.MemoryKind, @tagName(kind)),
            };
            const aligned_base = std.mem.alignForward(usize, e.base, std.heap.pageSize());
            const diff = aligned_base - e.base;
            const len = e.length - diff;

            desc.base_page = @intCast(aligned_base / std.heap.pageSize());
            desc.page_count = @intCast(@divFloor(len, std.heap.pageSize()));
        }
    }
    rsdp_addr = limine_reqs.rsdp_request.response.?.address;
    const hhdm_addr = @intFromPtr(hhdm_base());
    if (limine_reqs.framebuffer_request.response) |fbs_resp| {
        const fbs_raw = fbs_resp.framebuffers();
        framebuffers = try alloc.alloc(Framebuffer, fbs_raw.len);
        for (fbs_raw, framebuffers) |raw, *fb| {
            fb.* = .{
                .base = null,
                .phys_addr = @enumFromInt(@intFromPtr(raw.address) - hhdm_addr),
                .mode = .{
                    .model = util.convert_enum_by_name(FramebufferMemoryModel, raw.memory_model) orelse @panic(""),
                    .height = raw.height,
                    .width = raw.width,
                    .pitch = raw.pitch,
                    .bits_per_pixel = raw.bpp,
                },
                .edid = if (raw.edid) |p| .{ .size = raw.edid_size, .addr = @enumFromInt(@intFromPtr(p) - hhdm_addr) } else null,
            };
        }
    }
    if (limine_reqs.mp_request.response) |mp_resp| {
        smp = mp_resp.*;
        cpus = try alloc.alloc(limine.SmpInfo, smp.cpu_count);
        for (mp_resp.cpus(), 0..) |cpu, i| {
            cpus[i] = cpu.*;
        }
    }
}
