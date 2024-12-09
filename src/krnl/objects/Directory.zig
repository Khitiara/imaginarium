const ob = @import("ob.zig");
const Object = ob.Object;
const std = @import("std");
const Directory = @This();
const UUID = @import("zuid").UUID;
const QueuedSpinLock = @import("../hal/hal.zig").QueuedSpinLock;

header: Object,
lock: QueuedSpinLock = .{},
children: std.StringArrayHashMapUnmanaged(*Object) = .{},

const vtable: Object.VTable = .{
    .deinit = &ob.DeinitImpl(Object, Directory, "header").deinit_inner,
    .resolve = &resolve,
    .insert = &insert_impl,
};

fn resolve(o: *Object, alloc: std.mem.Allocator, path: [:0]const u8) Object.ResolveError!*Object {
    const name, const rest = ob.name.split(path) orelse return error.InvalidPath;
    const dir: *Directory = @fieldParentPtr("header", o);
    if (b: {
        var token: QueuedSpinLock.Token = undefined;
        dir.lock.lock(&token);
        defer token.unlock();
        break :b dir.children.get(name);
    }) |child| {
        if (rest.len > 0) {
            return try child.resolve(alloc, rest);
        } else {
            return child;
        }
    }
    return error.NotFound;
}

pub fn insert(dir: *Directory, alloc: std.mem.Allocator, obj: *Object, name: []const u8) !?*Object {
    const result = b: {
        var token: QueuedSpinLock.Token = undefined;
        dir.lock.lock(&token);
        defer token.unlock();
        break :b try dir.children.getOrPutValue(alloc, name, obj);
    };
    return if (result.found_existing) result.value_ptr.* else null;
}

fn insert_impl(o: *Object, alloc: std.mem.Allocator, obj: *Object, path: [:0]const u8) Object.InsertError!void {
    const name, const rest = ob.name.split(path) orelse return error.InvalidPath;
    const dir: *Directory = @fieldParentPtr("header", o);
    var token: QueuedSpinLock.Token = undefined;
    dir.lock.lock(&token);
    defer token.unlock();
    if (dir.children.get(name)) |child| {
        try child.insert(alloc, obj, rest);
        return;
    }
    if (rest.len == 0) {
        try dir.children.put(alloc, name, obj);
    } else {
        return error.NotFound;
    }
}

pub fn deinit(self: *Directory, alloc: std.mem.Allocator) void {
    self.children.deinit(alloc);
    alloc.destroy(self);
}

pub fn init(alloc: std.mem.Allocator) !*Directory {
    const dir = try alloc.create(Directory);
    dir.* = .{
        .header = .{
            .id = UUID.new.v4(),
            .vtable = &vtable,
            .kind = .directory,
        },
    };
    return dir;
}
