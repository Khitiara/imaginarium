const std = @import("std");

pub const Leaf = enum(u32) {
    //base
    max_level_and_vendor = 0,
    type_fam_model_stepping_features = 1,
    feature_flags = 7,
    freq_1 = 0x15,
    freq_2 = 0x16,
    // extended
    extended_fam_model_stepping_features = 0x80000001,
    capabilities = 0x80000007,
    extended_address_info = 0x80000008,
    svm = 0x8000000A,
    // hypervisor
    hypervisor_vendor = 0x40000000,
    hypervisor_frequencies = 0x40000010,
};

pub fn Subleaf(comptime leaf: Leaf) type {
    switch (leaf) {
        else => return void,
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

pub const CpuFeatures = packed struct(u32) {
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
};

pub const CpuFeatures2 = packed struct(u32) {
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

pub const ExtendedFeatures2 = packed struct(u32) {
    fpu: bool,
    vme: bool,
    de: bool,
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
    _reserved2: u1 = 0,
    mp: bool,
    nx: bool,
    _reserved3: u1 = 0,
    mmx_plus: bool,
    mmx: bool,
    fxsr: bool,
    ffxsr: bool,
    pg1g: bool,
    tscp: bool,
    _reserved4: u1 = 0,
    lm: bool,
    _3dnow_plus: bool,
    _3dnow: bool,
};

pub const ExtendedFeatures1 = packed struct(u32) {
    ahf64: bool,
    cmp: bool,
    svm: bool,
    eas: bool,
    cr8d: bool,
    lzcnt: bool,
    sse4a: bool,
    msse: bool,
    _3dnow_p: bool,
    osvw: bool,
    ibs: bool,
    xop: bool,
    skinit: bool,
    wdt: bool,
    _reserved5: u1 = 0,
    lwp: bool,
    fma4: bool,
    tce: bool,
    _reserved6: u1 = 0,
    nodeid: bool,
    _reserved7: u1 = 0,
    tbm: bool,
    topx: bool,
    pcx_core: bool,
    pcx_nb: bool,
    _reserved8: u1 = 0,
    dbx: bool,
    perftsc: bool,
    pcx_l1i_l3: bool,
    monx: bool,
    _reserved9: u2 = 0,
};

pub const ExtendedBrandPackage = packed struct(u32) {
    brand: u16,
    _: u12,
    package_type: u4,
};

pub const Flags1 = packed struct(u32) {
    _reserved1: u2 = 0,
    avx512qvnniw: bool,
    avx512qfma: bool,
    _reserved2: u14,
    pconfig: bool,
    _reserved3: u7 = 0,
    ibrs_ibpb: bool,
    stibp: bool,
    _reserved4: u4 = 0,
};

pub const Flags2 = packed struct(u32) {
    prefetchwt1: bool,
    avx512vbmi: bool,
    umip: bool,
    pku: bool,
    ospke: bool,
    _reserved5: u1 = 0,
    avx512vbmi2: bool,
    cet: bool,
    gfni: bool,
    vaes: bool,
    vpcl: bool,
    avx512vnni: bool,
    avx512bitalg: bool,
    tme: bool,
    avx512vp_dq: bool,
    _reserved6: u1 = 0,
    la57: bool,
    mawau: u5,
    rdpid: bool,
    _reserved7: u7 = 0,
    sgx_lc: bool,
    _reserved8: u1 = 0,
};

pub const Flags3 = packed struct(u32) {
    fsgsbase: bool,
    tsc_adjust: bool,
    sgx: bool,
    bmi1: bool,
    hle: bool,
    avx2: bool,
    ffdp: bool,
    smep: bool,
    bmi2: bool,
    erms: bool,
    invpcid: bool,
    rtm: bool,
    pqm: bool,
    fpcsds: bool,
    mpx: bool,
    pqe: bool,
    avx512f: bool,
    avx512dq: bool,
    rdseed: bool,
    adx: bool,
    smap: bool,
    avx512ifma: bool,
    pcommit: bool,
    clflushopt: bool,
    clwb: bool,
    pt: bool,
    avx512pf: bool,
    avx512er: bool,
    avx512cd: bool,
    sha: bool,
    avx512bw: bool,
    avx512vl: bool,
};

pub const SvmRevisionPresence = packed struct(u32) {
    revision: u8,
    present: bool,
    _: u23,
};

pub const SvmSubFeatures = packed struct(u32) {
    nested_paging: bool,
    lbr_virt: bool,
    svm_lock: bool,
    nrip_save_on_vmexit: bool,
    tsc_rate_msr: bool,
    vmcb_clean_bits: bool,
    flush_by_asid: bool,
    decode_assists: bool,
    _r1: u1 = 0,
    ssse3_and_sse5a_disable: bool,
    pause_filter: bool,
    _r2: u1 = 0,
    pause_filter_threshold: bool,
    avic: bool,
    _r3: u1 = 0,
    vls: bool,
    vgif: bool,
    _r4: u15 = 0,
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
            features2: CpuFeatures2,
            features: CpuFeatures,
        },
        .extended_address_info => extern struct {
            address_size_info: packed struct(u32) {
                physical_address_bits: u8,
                virtual_address_bits: u8,
                guest_physical_address_bits: u8,
                _: u8 = 0,
            },
            _: [3]u32,
        },
        .extended_fam_model_stepping_features => extern struct {
            type_fam_model_stepping: TypeFamModelStepping,
            brand_package: ExtendedBrandPackage,
            features1: ExtendedFeatures1,
            features2: ExtendedFeatures2,
        },
        .feature_flags => extern struct {
            _: u32 = 0,
            flags3: Flags3,
            flags2: Flags2,
            flags1: Flags1,
        },
        .freq_1 => extern struct {
            denominator: u32,
            numerator: u32,
            core_freq: u32,
            _: u32 = 0,
        },
        .freq_2 => extern struct {
            core_base: u16 align(4),
            core_max: u16 align(4),
            bus_reference: u16 align(4),
            _: u32 = 0,
        },
        .capabilities => extern struct {
            monitors: u8,
            version: u8,
            max_wrap_ms: u16,
            ras: packed struct(u32) {
                mca_overflow_recovery: bool,
                succor: bool,
                hwa: bool,
                scmca: bool,
                _: u28 = 0,
            },
            accum_gtsc_ratio: u32,
            enhanced_power_management: packed struct(u32) {
                temp_sensor: bool,
                frequency_id: bool,
                voltage_id: bool,
                thermal_trip: bool,
                thermal_monitoring: bool,
                software_thermal_control: bool,
                mul100: bool,
                hwps: bool,
                itsc: bool,
                cpb: bool,
                efro: bool,
                pfi: bool,
                processor_accumulator: bool,
                connected_standby: bool,
                running_average_power_limit: bool,
                _: u17 = 0,
            },
        },
        .svm => extern struct {
            revision_presence: SvmRevisionPresence,
            asid_count: u32,
            _: u32 = 0,
            sub_features: SvmSubFeatures,
        },
        .hypervisor_vendor => extern struct {
            eax: u32 = 0,
            vendor_id: [12]u8 align(4),
        },
        .hypervisor_frequencies => extern struct {
            tsc_freq_khz: u32,
            bus_freq_khz: u32,
            _1: u32 = 0,
            _2: u32 = 0,
        },
    };
}

inline fn normalize_subleaf(comptime leaf: Leaf, comptime subleaf: Subleaf(leaf)) u32 {
    switch (@typeInfo(Subleaf(leaf))) {
        .int => return @intCast(subleaf),
        .@"enum" => return @intFromEnum(subleaf),
        .void => return 0,
        else => unreachable,
    }
}

pub inline fn cpuid(comptime leaf: Leaf, comptime subleaf: Subleaf(leaf)) CpuidOutputType(leaf, subleaf) {
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
