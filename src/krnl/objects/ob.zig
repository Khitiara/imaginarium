const Thread = @import("../thread/Thread.zig");
const wait_block = @import("../dispatcher/dispatcher.zig").wait_block;
const util = @import("util");
const queue = util.queue;
const zuid = @import("zuid");
const std = @import("std");

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

pub const ObjectKindAndLock = packed struct(u8) {
    kind: ObjectKind,
    lock: bool,
};

pub const ObNamespace = zuid.deserialize("2d7e52f8-0d27-4a40-a967-828c2900c33c");

pub const Object = extern struct {
    kind: ObjectKind,
    id: zuid.Uuid = zuid.null_uuid,
    /// max-value means the object is unnamed
    name_idx: u32 = std.math.maxInt(u32),
    wait_queue: queue.Queue(wait_block.WaitBlock, "wait_queue") = .{},

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
