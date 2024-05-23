const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const DiskImage = @This();
const fs = std.fs;
const io = std.io;

step: Step,
basename: []const u8,
output_file: std.Build.GeneratedFile,
sources: std.ArrayListUnmanaged(LazyPath),

pub const base_id: Step.Id = .custom;

pub const Options = struct {
    basename: ?[]const u8 = null,
    sources: ?[]LazyPath = null,
};

pub fn create(
    owner: *std.Build,
    options: Options,
) *DiskImage {
    const self = owner.allocator.create(DiskImage) catch @panic("OOM");
    self.* = DiskImage{
        .step = Step.init(.{
            .id = base_id,
            .name = owner.fmt("diskimage {s}", .{options.basename orelse "disk.bin"}),
            .owner = owner,
            .makeFn = make,
        }),
        .basename = options.basename orelse "disk.bin",
        .output_file = .{ .step = &self.step },
        .sources = std.ArrayListUnmanaged(LazyPath).fromOwnedSlice(options.sources orelse &[0]LazyPath{}),
    };
    for (self.sources.items) |f| {
        f.addStepDependencies(&self.step);
    }
    return self;
}

pub fn append(self: *DiskImage, file: LazyPath) void {
    self.sources.append(self.step.owner.allocator, file) catch @panic("OOM");
    file.addStepDependencies(&self.step);
}

pub fn getOutput(self: *const DiskImage) std.Build.LazyPath {
    return .{ .generated = .{ .file = &self.output_file } };
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    const b = step.owner;
    const self: *DiskImage = @fieldParentPtr("step", step);

    var man = b.graph.cache.obtain();
    defer man.deinit();

    // Random bytes to make DiskImage unique. Refresh this with new random
    // bytes when DiskImage implementation is modified incompatibly.
    man.hash.add(@as(u32, 0xE890CDA2));
    for (self.sources.items) |f| {
        const full_src_path = f.getPath2(b, step);
        _ = try man.addFile(full_src_path, null);
    }

    if (try step.cacheHit(&man)) {
        // Cache hit, skip subprocess execution.
        const digest = man.final();
        self.output_file.path = try b.cache_root.join(b.allocator, &.{
            "o", &digest, self.basename,
        });
        return;
    }

    prog_node.setEstimatedTotalItems(self.sources.items.len);

    const digest = man.final();
    const cache_path = "o" ++ fs.path.sep_str ++ digest;
    const dir = b.cache_root.handle.makeOpenPath(cache_path, .{}) catch |err| {
        return step.fail("unable to make path '{}{s}': {s}", .{
            b.cache_root, cache_path, @errorName(err),
        });
    };

    self.output_file.path = try b.cache_root.join(b.allocator, &.{
        "o", &digest, self.basename,
    });
    const write = dir.createFile(self.basename, .{}) catch |err| {
        return step.fail("unable to make path '{s}': {s}", .{
            self.output_file.path.?, @errorName(err),
        });
    };
    defer write.close();

    // q35 qemu device doesnt boot from raw images less than this many bytes
    // https://stackoverflow.com/a/68750259
    // so use setEndPos to expand the file ahead of time.
    // the write head remains at the beginning of the file and it can still expand if we write more than this amount
    // we do this at the start so it doesnt truncate if we manage to get past this limit naturally
    try write.setEndPos(515585);

    for (self.sources.items) |f| {
        const full_src_path = f.getPath2(b, step);
        const read = try fs.openFileAbsolute(full_src_path, .{});
        defer read.close();
        try write.writeFileAll(read, .{});
        prog_node.completeOne();
    }

    try step.writeManifest(&man);
}
