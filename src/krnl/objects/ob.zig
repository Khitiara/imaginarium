const Thread = @import("../thread/Thread.zig");
const dispatcher = @import("../dispatcher/dispatcher.zig");
const WaitBlock = dispatcher.WaitBlock;
const util = @import("util");
const queue = util.queue;
const zuid = @import("zuid");
const std = @import("std");
const atomic = std.atomic;

pub const Directory = @import("Directory.zig");

pub const root: Directory = .{
    .header = .{
        .kind = .directory,
        .id = zuid.new.v5(namespace, "/?"),
    },
};

pub const ObjectKind = enum(u7) {
    directory,
    semaphore,
    thread,
    interrupt,
    device,
    driver,
    _,

    pub inline fn ObjectType(self: ObjectKind) type {
        return switch (self) {
            .thread => Thread,
            .semaphore => Thread.Semaphore,
        };
    }
};

pub const namespace = zuid.deserialize("2d7e52f8-0d27-4a40-a967-828c2900c33c");

pub fn TypedRef(T: type) type {
    return opaque {
        fn hdr(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, Object) {
            return @ptrCast(self);
        }

        pub fn ptr(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, T) {
            return self.hdr.ptr_assert(T) catch unreachable;
        }

        pub fn release(self: *@This(), alloc: std.mem.Allocator) void {
            if (self.hdr().pointer_count.fetchSub(1, .seq_cst) == 1) {
                self.deinit(alloc);
            }
        }

        pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
            self.ptr().deinit(alloc);
        }
    };
}

/// An opaque view of an object. Pointers to this are the kernel-mode equivalent of handles, and are ref-counted
/// separately from handles, as handles exist to allow use in usermode where pointers to kernel-mode memory
/// are invalid.
pub const Ref = opaque {
    fn hdr(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, Object) {
        return @ptrCast(self);
    }

    pub fn ptr(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, anyopaque) {
        return self.hdr().ptr();
    }

    pub fn ptr_assert(self: anytype, comptime Assert: type) util.CopyPtrAttrs(@TypeOf(self), .One, Assert) {
        return self.hdr().ptr_assert(Assert);
    }

    pub fn clone(self: anytype) @TypeOf(self) {
        _ = self.hdr().pointer_count.fetchAdd(1, .seq_cst);
        return self;
    }

    pub fn release(self: *Ref, alloc: std.mem.Allocator) void {
        if (self.hdr().pointer_count.fetchSub(1, .seq_cst) == 1) {
            self.deinit(alloc);
        }
    }

    pub fn deinit(self: *const Ref, alloc: std.mem.Allocator) void {
        const h = self.hdr();
        switch (h.kind) {
            inline else => |typ| {
                const T: type = typ.ObjectType();
                T.deinit(try h.ptr_assert(T), alloc);
            },
        }
    }

    pub fn resolve(self: anytype, alloc: std.mem.Allocator, path: [:0]const u8, options: anytype) *Ref {
        const h = self.hdr();
        switch (h.kind) {
            inline else => |typ| {
                const T: type = typ.ObjectType();
                return T.resolve(try h.ptr_assert(T), alloc, path, options);
            },
        }
    }
};

pub const Object = struct {
    kind: ObjectKind,
    id: zuid.Uuid align(8),
    /// kernel-mode users can copy a pointer using this refcount, thereby avoiding
    /// the need to potentially allocate in the handle table
    pointer_count: atomic.Value(u64) = atomic.Value(u64).init(0),
    /// usermode cant get a pointer to a kernel-mode object, and certainly not a useful one
    /// thus for usermode references we use a true handle table
    handle_count: atomic.Value(u64) = atomic.Value(u64).init(0),

    // if you need a specific type either ptrCast it or call ptr_assert
    pub fn ptr(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, anyopaque) {
        switch (self.kind) {
            inline else => |typ| {
                const T: type = typ.ObjectType();
                const Ptr = util.CopyPtrAttrs(@TypeOf(self), .One, T);
                return @ptrCast(@as(Ptr, @fieldParentPtr("header", self)));
            },
        }
    }

    pub fn ptr_assert(self: anytype, comptime Assert: type) !util.CopyPtrAttrs(@TypeOf(self), .One, Assert) {
        const Ptr = util.CopyPtrAttrs(@TypeOf(self), .One, Assert);
        switch (self.kind) {
            inline else => |typ| {
                if (typ.ObjectType() != Assert) {
                    return error.dispatcher_object_wrong_type;
                }
                return @ptrCast(@as(Ptr, @fieldParentPtr("header", self)));
            },
        }
    }

    pub fn ref(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, Ref) {
        const RefPtr = util.CopyPtrAttrs(@TypeOf(self), .One, Ref);
        return @as(RefPtr, @ptrCast(self)).clone();
    }
};
