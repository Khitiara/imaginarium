const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const entries = paging.entries;
const std = @import("std");

// the base where we plan to id-map
const idmap_base: isize = -1 << 45;


