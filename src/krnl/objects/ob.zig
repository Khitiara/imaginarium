const Thread = @import("../thread/Thread.zig");
const dispatcher = @import("../dispatcher/dispatcher.zig");
const WaitBlock = dispatcher.WaitBlock;
const util = @import("util");
const queue = util.queue;
const io = @import("../io/io.zig");
const zuid = @import("zuid");
const std = @import("std");
const atomic = std.atomic;

pub const name = @import("name.zig");

pub const Directory = @import("Directory.zig");

pub var root: *Directory = undefined;

pub const ObjectKind = enum(u7) {
    directory,
    semaphore,
    thread,
    // interrupt,
    device,
    driver,
    _,
};

pub const namespace = zuid.deserialize("2d7e52f8-0d27-4a40-a967-828c2900c33c");

var initialized: bool = false;

pub fn init(alloc: std.mem.Allocator) !void {
    if (@cmpxchgStrong(bool, &initialized, false, true, .acq_rel, .monotonic) != null) return;
    root = try .init(alloc);
}

pub fn insert(alloc: std.mem.Allocator, object: *Object, n: [:0]const u8) !void {
    try init(alloc);

    if (name.split(n)) |s| {
        if (std.mem.eql(u8, s[0], "/?")) {
            return root.header.insert(alloc, object, s[1]);
        } else {
            return error.UnknownRoot;
        }
    } else {
        return error.InvalidPath;
    }
}

pub inline fn DeinitImpl(comptime Parent: type, comptime T: type, comptime field_name: []const u8) type {
    return struct {
        pub fn deinit_inner(self: *Parent, alloc: std.mem.Allocator) void {
            @as(*T, @fieldParentPtr(field_name, self)).deinit(alloc);
        }
        pub fn deinit_outer(self: *T, alloc: std.mem.Allocator) void {
            self.vtable.deinit(self, alloc);
        }
    };
}

fn no_resolve(_: *Object, _: std.mem.Allocator, _: [:0]const u8) !*Object {
    return error.Unsupported;
}
fn no_insert(_: *Object, _: std.mem.Allocator, _: *Object, _: [:0]const u8) !void {
    return error.Unsupported;
}

pub const Object = struct {
    kind: ObjectKind,
    id: zuid.UUID align(8),
    /// kernel-mode users can copy a pointer using this refcount, thereby avoiding
    /// the need to potentially allocate in the handle table
    pointer_count: atomic.Value(u64) = .init(0),
    /// usermode cant get a pointer to a kernel-mode object, and certainly not a useful one
    /// thus for usermode references we use a true handle table
    handle_count: atomic.Value(u64) = .init(0),
    vtable: *const VTable,

    pub const VTable = struct {
        resolve: ?*const fn (self: *Object, alloc: std.mem.Allocator, path: [:0]const u8) ResolveError!*Object = null,
        insert: ?*const fn (self: *Object, alloc: std.mem.Allocator, ob: *Object, path: [:0]const u8) InsertError!void = null,
        deinit: *const fn (self: *Object, alloc: std.mem.Allocator) void,
    };

    pub const ResolveError = error{ NotFound, InvalidPath, Unsupported } || std.mem.Allocator.Error;
    pub const InsertError = error{ NotFound, InvalidPath, Unsupported } || std.mem.Allocator.Error;

    pub fn resolve(self: *Object, alloc: std.mem.Allocator, path: [:0]const u8) ResolveError!*Object {
        return (self.vtable.resolve orelse &no_resolve)(self, alloc, path);
    }

    pub fn insert(self: *Object, alloc: std.mem.Allocator, ob: *Object, path: [:0]const u8) InsertError!void {
        return (self.vtable.insert orelse &no_insert)(self, alloc, ob, path);
    }

    pub fn add_ref(self: anytype) @TypeOf(self) {
        _ = self.pointer_count.fetchAdd(1, .monotonic);
        return self;
    }

    pub fn release(self: *Object, alloc: std.mem.Allocator) void {
        if (self.pointer_count.fetchSub(1, .release) == 1) {
            _ = self.pointer_count.load(.acquire);
            self.vtable.deinit(self, alloc);
        }
    }
};
