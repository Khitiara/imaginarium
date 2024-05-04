const Thread = @import("Thread.zig");
const util = @import("util");
const queue = util.queue;

pub const InterruptRequestPriority = enum(u4) {
    passive = 0x0,
    dispatch = 0x1,
    dev_0 = 0x2,
    dev_1 = 0x3,
    dev_2 = 0x4,
    dev_3 = 0x5,
    dev_4 = 0x6,
    dev_5 = 0x7,
    dev_6 = 0x8,
    dev_7 = 0x9,
    dev_8 = 0xA,
    dev_9 = 0xB,
    sync = 0xC,
    clock = 0xD,
    ipi = 0xE,
    high = 0xF,
};

pub const wait_block = @import("dispatcher/wait_block.zig");

pub const DispatcherObjectKind = enum(u7) {
    semaphore,
    thread,
    interrupt,
    _,

    pub inline fn ObjectType(self: DispatcherObjectKind) type {
        return switch (self) {
            .thread => Thread,
            .semaphore => Thread.Semaphore,
        };
    }
};

pub const DispatcherObjectKindAndLock = packed struct(u8) {
    kind: DispatcherObjectKind,
    lock: bool,
};

pub const DispatcherObject = extern struct {
    kind: DispatcherObjectKind,
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
