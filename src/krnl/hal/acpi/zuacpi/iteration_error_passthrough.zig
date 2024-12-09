const std = @import("std");
const arch = @import("../../arch/arch.zig");
const uacpi = @import("../uacpi/uacpi.zig");
const namespace = uacpi.namespace;

pub inline fn IterationErrorPasser(comptime E: type) type {
    return struct {
        const IterationErrorPasserImpl = @This();
        const PossibleErrors = E || uacpi.Error;

        pub const Callback = fn (user: ?*anyopaque, node: *namespace.NamespaceNode, depth: u32) E!namespace.IterationDecision;

        pub const IterationContext = struct {
            user: ?*anyopaque,
            // stack: ?*std.builtin.StackTrace,
            err: ?E = null,
        };

        pub fn create_callback(comptime cb: Callback) namespace.IterationCallback {
            return struct {
                pub fn iteration_callback_impl(ctx_raw: ?*anyopaque, node: *namespace.NamespaceNode, depth: u32) callconv(arch.cc) namespace.IterationDecision {
                    const ctx: *IterationContext = @alignCast(@ptrCast(ctx_raw.?));

                    return cb(ctx.user, node, depth) catch |err| {
                        // if (@errorReturnTrace()) |trace| if (ctx.stack) |existing_stack| {
                        //     const frames = trace.index + existing_stack.index;
                        //     existing_stack.index += trace.index;
                        //     if (frames >= existing_stack.instruction_addresses.len) {
                        //         @memcpy(existing_stack.instruction_addresses[existing_stack.index..], trace.instruction_addresses[0..trace.index]);
                        //     }
                        //     // else if (existing_stack.index <= existing_stack.instruction_addresses.len) b: {
                        //     //     const alloc = arch.vmm.gpa.allocator();
                        //     //     const addrs = std.mem.concat(alloc, usize, &.{ existing_stack.instruction_addresses[0..existing_stack.index], trace.instruction_addresses }) catch break :b;
                        //     //     existing_stack.instruction_addresses = addrs;
                        //     // }
                        // };
                        ctx.err = err;
                        return .@"break";
                    };
                }
            }.iteration_callback_impl;
        }
    };
}
