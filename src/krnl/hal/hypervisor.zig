const cpuid = @import("arch/x86_64/cpuid.zig");
const SvmInfo = cpuid.CpuidOutputType(.svm, {});
const std = @import("std");
const log = std.log.scoped(.hypervisor);

pub var present: bool = false;
var sub_features: cpuid.SvmSubFeatures = undefined;
var asid_count: u32 = undefined;

pub const KnownHypervisor = union(enum) {
    kvm: struct {
        max_hypervisor_leaf: u32,
    },
    unknown: [12]u8,
    none,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (!std.mem.eql(u8, "s", fmt)) {
            return error.InvalidFormat;
        }
        switch (self) {
            .kvm => |kvm| {
                try writer.print("KVM Hypervisor, max hypervisor cpuid leaf: {x:0>8}", .{kvm.max_hypervisor_leaf});
            },
            .unknown => |un| {
                try writer.print("Unknown hypervisor, vendor \"{s}\"", .{un});
            },
            .none => {
                try writer.print("No hypervisor", .{});
            },
        }
    }
};

pub var hypervisor: KnownHypervisor = .none;

pub fn init() void {
    const info: SvmInfo = cpuid.cpuid(.svm, {});
    const tfmsf = cpuid.cpuid(.type_fam_model_stepping_features, {});
    present = @import("config").force_hypervisor or tfmsf.features2.hv or info.revision_presence.present;
    sub_features = info.sub_features;
    asid_count = info.asid_count;

    const hypervisor_info = cpuid.cpuid(.hypervisor_vendor, {});
    if (std.mem.eql(u8, "KVMKVMKVM" ++ .{ 0, 0, 0 }, &hypervisor_info.vendor_id)) {
        hypervisor = .{ .kvm = .{ .max_hypervisor_leaf = hypervisor_info.eax } };
    }

    log.info("{s}", .{hypervisor});
}
