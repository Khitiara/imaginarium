const util = @import("util");
const queue = util.queue;
const hal = @import("../hal/hal.zig");
const arch = hal.arch;
const std = @import("std");

var pool: std.heap.MemoryPool(InterruptRegistration) = undefined;

pub const InterruptRegistration = struct {
    entry: queue.DoublyLinkedNode = .{},
    routine: ServiceRoutine,
    context: ?*anyopaque,
    vector: hal.InterruptVector,
    pub noinline fn connect(options: struct {
        vector: hal.InterruptVector,
        routine: union {
            isr: ServiceRoutine,
        },
        context: *anyopaque,
    }) !*InterruptRegistration {
        const reg = try pool.create();
        reg.* = .{
            .routine = options.routine.isr,
            .vector = options.vector,
            .context = options.context,
        };

        queues[@as(u8,@bitCast(reg.vector))].add_back(reg);
        if (@cmpxchgStrong(bool, &raw_handlers[@as(u8,@bitCast(reg.vector))], false, true, .acq_rel, .monotonic) != true) {
            arch.idt.add_handler(.{ .vector = reg.vector }, &handle, .trap, 0, 0);
        }
        return reg;
    }

    pub fn deinit(self: *InterruptRegistration) void {
        queues[@as(u8,@bitCast(self.vector))].remove(self);
        pool.destroy(self);
    }
};

/// An interrupt service routine for a shareable IRQ handler.
pub const ServiceRoutine = *const fn (interrupt: *InterruptRegistration, context: ?*anyopaque) bool;

const ServiceRegistrationQueue = queue.DoublyLinkedList(InterruptRegistration, "entry");
var queues: []ServiceRegistrationQueue = undefined;
var raw_handlers: [256]bool = .{false} ** 256;

pub fn init() !void {
    const alloc = arch.vmm.gpa.allocator();
    queues = try alloc.alloc(ServiceRegistrationQueue, 256);
    @memset(queues, .{});
    pool = .init(alloc);
}

fn handle(frame: arch.idt.InterruptFrame(u64)) callconv(arch.cc) void {
    var node = queues[frame.vector.int].peek_front();
    while (node) |isr| : (node = ServiceRegistrationQueue.next(isr)) {
        if (isr.routine(isr, isr.context)) return;
    }
}
