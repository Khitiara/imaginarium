const std = @import("std");

pub const Leaf = enum(u32) {
    max_level_and_vendor = 0,
    type_fam_model_stepping_features = 1,
};

pub const TypeFamModelStepping = packed struct(u32) {
    stepping: u4,
    model: u4,
    family: u4,
    type: u2,
    ext_model: u4,
    ext_family: u8,
    _: u6,
};

pub const BrandFlushCountId = packed struct(u32) {
    brand: u8,
    cl_flush: u8,
    proc_count: u8,
    apic_id: u8,
};

pub const CpuFeatures = packed struct(u64) {
    fpu: bool,
    _: u63,
};

pub inline fn CpuidOutputType(comptime leaf: Leaf) type {
    return switch (leaf) {
        .max_level_and_vendor => extern struct {
            max_level: u32,
            vendor_id: [3]u32,

            const Self = @This();
            pub fn vendor_id_str(self: *const Self) []const u8 {
                return std.mem.sliceAsBytes(&self.vendor_id);
            }
        },
        .type_fam_model_stepping_features => extern struct {
            type_fam_model_stepping: TypeFamModelStepping,
            brand_flush_count_id: BrandFlushCountId,
            features: CpuFeatures align(4),
        },
    };
}

pub fn cpuid(comptime leaf: Leaf, comptime subleaf: u32) CpuidOutputType(leaf) {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var edx: u32 = undefined;
    var ecx: u32 = undefined;
    asm volatile (
        \\cpuid
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [edx] "={edx}" (edx),
          [ecx] "={ecx}" (ecx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
        : "memory"
    );
    var arr = [4]u32{ eax, ebx, ecx, edx };
    return @as(*CpuidOutputType(leaf), @ptrCast(&arr)).*;
}

test "cpuid vendor str" {
    const T = CpuidOutputType(.max_level_and_vendor);
    const t = T{
        .vendor_id = .{ 0x756E6547, 0x49656E69, 0x6C65746E },
        .max_level = 16,
    };
    try @import("std").testing.expectEqualStrings("GenuineIntel", t.vendor_id_str());
}
