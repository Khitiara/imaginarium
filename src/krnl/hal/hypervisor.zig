const cpuid = @import("arch/cpuid.zig");
const SvmInfo = cpuid.CpuidOutputType(.svm, {});
const std = @import("std");
const log = std.log.scoped(.hypervisor);

pub var present: bool = false;
var sub_features: cpuid.SvmSubFeatures = undefined;
var asid_count: u32 = undefined;

pub fn init() void {
    const info: SvmInfo = cpuid.cpuid(.svm, {});
    const tfmsf = cpuid.cpuid(.type_fam_model_stepping_features, {});
    present = @import("config").force_hypervisor or tfmsf.features2.hv or info.revision_presence.present;
    sub_features = info.sub_features;
    asid_count = info.asid_count;
}

