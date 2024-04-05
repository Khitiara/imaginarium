const std = @import("std");

pub const Leaf = enum(u32) {
    max_level_and_vendor = 0,
    type_fam_model_stepping_features = 1,
};

pub fn Subleaf(comptime leaf: Leaf) type {
    switch (leaf) {
        else => return u0,
    }
}

pub const TypeFamModelStepping = packed struct(u32) {
    stepping: u4,
    model: u4,
    family: u4,
    type: u2,
    ext_model: u4,
    ext_family: u8,
    _: u6 = 0,
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
    _reserved1: u1 = 0,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse36: bool,
    psn: bool,
    cflush: bool,
    _reserved2: u1 = 0,
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
    _reserved3: u1 = 0,
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

pub inline fn CpuidOutputType(comptime leaf: Leaf, comptime subleaf: Subleaf(leaf)) type {
    _ = subleaf; // not used by any leaf yet implemented
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
    return asm volatile (
        \\ pushfq
        \\ popq %rax
        \\ movq %rbx, %rax
        \\ xorq $0x0000000000200000, %rax
        \\ pushq %rax
        \\ popfq
        \\ pushfq
        \\ popq %rax
        \\ xorq %rbx, %rax
        : [supported] "={rax}" (-> u64),
        :
        : "flags", "rbx"
    ) != 0;
}

pub const CpuidError = error{cpuid_not_supported};

inline fn normalize_subleaf(comptime leaf: Leaf, comptime subleaf: Subleaf(leaf)) u32 {
    switch (@typeInfo(Subleaf(leaf))) {
        .Int => return @intCast(subleaf),
        .Enum => return @intFromEnum(subleaf),
        else => unreachable,
    }
}

pub inline fn cpuid(comptime leaf: Leaf, comptime subleaf: Subleaf(leaf)) !CpuidOutputType(leaf, subleaf) {
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
          [subleaf] "{ecx}" (normalize_subleaf(leaf, subleaf)),
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
