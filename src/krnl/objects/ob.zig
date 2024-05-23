const Thread = @import("../thread/Thread.zig");
const dispatcher = @import("../dispatcher/dispatcher.zig");
const WaitBlock = dispatcher.WaitBlock;
const util = @import("util");
const queue = util.queue;
const zuid = @import("zuid");
const std = @import("std");
const atomic = std.atomic;

pub const ObjectKind = enum(u7) {
    semaphore,
    thread,
    interrupt,
    _,

    pub inline fn ObjectType(self: ObjectKind) type {
        return switch (self) {
            .thread => Thread,
            .semaphore => Thread.Semaphore,
        };
    }
};

pub var ob_page_alloc: std.mem.Allocator = undefined;

pub const ObNamespace = zuid.deserialize("2d7e52f8-0d27-4a40-a967-828c2900c33c");

pub const ObjectRef = opaque {
    pub fn ptr(self: anytype) util.CopyPtrAttrs(@TypeOf(self), .One, anyopaque) {
        const Concrete = util.CopyPtrAttrs(@TypeOf(self), .One, Object);
        return @as(Concrete, @ptrCast(self)).ptr();
    }
    pub fn ptr_assert(self: anytype, comptime Assert: type) util.CopyPtrAttrs(@TypeOf(self), .One, Assert) {
        const Concrete = util.CopyPtrAttrs(@TypeOf(self), .One, Object);
        return @as(Concrete, @ptrCast(self)).ptr_assert(Assert);
    }
};

pub const Object = struct {
    kind: ObjectKind,
    id: zuid.Uuid align(8) = zuid.null_uuid,
    /// max-value means the object is unnamed
    name_idx: u32 = std.math.maxInt(u32),
    wait_lock: dispatcher.SpinLockIRQL = .{ .set_irql = .passive },
    wait_queue: queue.DoublyLinkedList(WaitBlock, "wait_queue") = .{},
    /// kernel-mode users can copy a pointer using this refcount, thereby avoiding
    /// the need to potentially allocate in the handle table
    pointer_count: atomic.Value(u64) = atomic.Value(u64).init(0),
    /// usermode cant get a pointer to a kernel-mode object, and certainly not a useful one
    /// thus for usermode references we use a true handle table
    handle_count: atomic.Value(u64) = atomic.Value(u64).init(0),
    vtable: *const ObjectFunctions,

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
};

pub const ObjectFunctions = struct {
    deinit: *const fn (*const Object, std.mem.Allocator) void,
    signal: *const fn (*Object) void,
};
