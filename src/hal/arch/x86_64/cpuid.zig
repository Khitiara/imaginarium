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
    vme: bool,
    dbg: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cx8: bool,
    apic: bool,
    _reserved1: u1,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse36: bool,
    psn: bool,
    cflush: bool,
    _reserved2: u1,
    dtes: bool,
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    ss: bool,
    htt: bool,
    tm1: bool,
    ia64: bool,
    pbe: bool,
    sse3: bool,
    pclmul: bool,
    dtes64: bool,
    mon: bool,
    dscpl: bool,
    vmx: bool,
    smx: bool,
    est: bool,
    tm2: bool,
    ssse3: bool,
    cid: bool,
    sdbg: bool,
    fma: bool,
    cx16: bool,
    etprd: bool,
    pdcm: bool,
    _reserved3: u1,
    pcid: bool,
    dca: bool,
    sse41: bool,
    sse42: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    tscd: bool,
    aes: bool,
    xsave: bool,
    osxsave: bool,
    avx: bool,
    f16c: bool,
    rdrand: bool,
    hv: bool,
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

pub fn check_cpuid_supported() bool {
    cpuid_supported = asm volatile (
        \\ pushfq
        \\ movl %eax, %ecx
        \\ popq %rax
        \\ xorl $0x00200000, %eax
        \\ pushq %rax
        \\ popfq
        \\ pushfq
        \\ popq %rax
        \\ pushq %rcx
        \\ popfq
        \\ xorl %ecx, %eax
        : [supported] "={eax}" (-> bool),
        :
        : "flags", "memory", "ecx"
    );
    return cpuid_supported.?;
}

var cpuid_supported: ?bool = null;

pub const CpuidError = error{cpuid_not_supported};

pub fn cpuid(comptime leaf: Leaf, comptime subleaf: u32) !CpuidOutputType(leaf) {
    if (!(cpuid_supported orelse check_cpuid_supported()))
        return error.cpuid_not_supported;

    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var edx: u32 = undefined;
    var ecx: u32 = undefined;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [edx] "={edx}" (edx),
          [ecx] "={ecx}" (ecx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
        : "memory"
    );
    const arr = [4]u32{ eax, ebx, ecx, edx };
    return @bitCast(arr);
}

test "cpuid vendor str" {
    const T = CpuidOutputType(.max_level_and_vendor);
    const t = T{
        .vendor_id = .{ 0x756E6547, 0x49656E69, 0x6C65746E },
        .max_level = 16,
    };
    try @import("std").testing.expectEqualStrings("GenuineIntel", t.vendor_id_str());
}
