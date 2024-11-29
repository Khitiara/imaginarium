const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

var named_modules: std.StringArrayHashMap(*Build.Module) = undefined;

pub fn init(b: *Build) void {
    named_modules = .init(b.allocator);
}

pub fn name_module(name: []const u8, module: *Build.Module) void {
    named_modules.putNoClobber(name, module) catch @panic("OOM");
}

pub fn addImportFromTable(module: *Build.Module, name: []const u8) void {
    if (named_modules.get(name)) |d| {
        module.addImport(name, d);
    }
}

pub fn installFrom(b: *Build, dep: *Build.Step, group_step: *Build.Step, file: LazyPath, dir: []const u8, rel: []const u8) void {
    const s = b.addInstallFileWithDir(file, .{ .custom = dir }, rel);
    s.step.dependOn(dep);
    group_step.dependOn(&s.step);
}