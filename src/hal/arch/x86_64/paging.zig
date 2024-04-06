pub const entries = @import("paging/page_table_entry.zig");
pub const pkru = @import("paging/pkru.zig");

const cpuid = @import("cpuid.zig");

pub const PagingFeatures = packed struct {
    maxphyaddr: u8,
    linear_address_width: u8,
    five_level_paging: bool,
    gigabyte_pages: bool,
    global_page_support: bool,
};

pub fn enumerate_paging_features() PagingFeatures {
    const addresses = cpuid.cpuid(.extended_address_info, 0).address_size_info;
    const feats_base = cpuid.cpuid(.type_fam_model_stepping_features, 0);
    const feats_ext = cpuid.cpuid(.extended_fam_model_stepping_features, 0);
    const flags = cpuid.cpuid(.feature_flags, 0);
    return PagingFeatures{
        .maxphyaddr = addresses.physical_address_bits,
        .linear_address_width = addresses.virtual_address_bits,
        .five_level_paging = flags.flags2.la57,
        .gigabyte_pages = feats_ext.features.pg1g,
        .global_page_support = feats_base.features.pge,
    };
}

test {
    @import("std").testing.refAllDecls(entries);
    @import("std").testing.refAllDecls(@This());
}
