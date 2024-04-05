const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const DiskImage = @This();
const fs = std.fs;
const io = std.io;

step: Step,
sources: std.ArrayListUnmanaged(LazyPath),
basename: []const u8,
output_file: std.Build.GeneratedFile,

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
    self.* = .{
        .step = Step.init(.{
            .id = base_id,
            .name = "diskimage",
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
    return .{ .generated = &self.output_file };
}

fn make(step: *Step, prog_node: *std.Progress.Node) !void {
    const b = step.owner;
    const self: *DiskImage = @fieldParentPtr("step", step);

    var man = b.graph.cache.obtain();
    defer man.deinit();

    // Random bytes to make ObjCopy unique. Refresh this with new random
    // bytes when ObjCopy implementation is modified incompatibly.
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
    const write = try dir.createFile(self.basename, .{});
    defer write.close();

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
