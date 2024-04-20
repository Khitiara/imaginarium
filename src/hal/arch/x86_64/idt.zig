const std = @import("std");
const descriptors = @import("descriptors.zig");
const gdt = @import("gdt.zig");

pub const GateType = enum(u4) {
    interrupt = 0xE,
    trap = 0xF,
    _,
};

pub const Interrupt = enum(u8) {
    divide_by_zero,
    debug,
    nmi,
    breakpoint,
    overflow,
    bound_range_exceeded,
    invalid_opcode,
    device_not_available,
    double_fault,
    coprocessor_segment_overrun,
    invalid_tss,
    segment_not_present,
    general_protection_fault,
    page_fault,
    x87_fp_exception = 0x10,
    alignment_check,
    machine_check,
    simd_fp_exception,
    virtualization_exception,
    security = 0x1E,
    _,
    pub fn has_error_code(self: Interrupt) bool {
        return switch (self) {
            .double_fault, .invalid_tss, .segment_not_present, .general_protection_fault, .page_fault, .security => true,
            else => false,
        };
    }
};

pub const InterruptGateDescriptor = packed struct(u128) {
    offset_low: u16,
    segment_selector: descriptors.Selector,
    ist: u3,
    _reserved1: u5 = 0,
    type: GateType,
    _reserved2: u1 = 0,
    dpl: u2,
    present: bool,
    offset_upper: u48,
    _reserved3: u32 = 0,

    pub fn init(addr: usize, ist: u3, typ: GateType, dpl: u2) InterruptGateDescriptor {
        return .{
            .offset_low = @truncate(addr),
            .segment_selector = gdt.selectors.kernel_code,
            .ist = ist,
            .type = typ,
            .dpl = dpl,
            .present = true,
            .offset_upper = @truncate(addr >> 16),
        };
    }

    pub const nul = InterruptGateDescriptor.init(0, 0, @enumFromInt(0), 0, false);
};

const RawHandler = fn () callconv(.Naked) void;
pub const InterruptHandler = *const fn (*InterruptFrame) callconv(.SysV) void;

pub const SavedRegisters = extern struct {
    // TODO push the other registers and stuff
    rdx: u64,
    rax: u64,
};

pub const InterruptFrame = extern struct {
    registers: SavedRegisters align(8),
    interrupt_number: Interrupt align(8),
    error_code: usize,
    ss: descriptors.Selector align(8),
    rip: usize,
    cs: descriptors.Selector align(8),
    eflags: @import("../x86_64.zig").Flags,
    rsp: usize,
};

comptime {
    var regscnt = 0;
    var push: []const u8 = "\n";
    var pop: []const u8 = "\n";

    for (@typeInfo(SavedRegisters).Struct.fields) |reg| {
        push = "\n    pushq %" ++ reg.name ++ push;
        pop = pop ++ "    popq %" ++ reg.name ++ "\n";
        regscnt += 8;
    }

    const code: []const u8 =
        \\ .global __isr_common;
        \\ .type __isr_common, @function;
        \\ __isr_common:
    ++ push ++ "    movsbq   " ++ std.fmt.comptimePrint("{d}", .{regscnt}) ++ "(%rsp), %rdx\n" ++
        \\     movq     %rsp, %rdi
        \\     callq    *__isrs(, %rdx, 8)
    ++ pop ++
        \\     add      $16, %rsp
        \\     iretq
    ;
    asm (code);
}

export var idt: [256]InterruptGateDescriptor = undefined;
export var __isrs: [256]InterruptHandler = undefined;

fn make_handler(comptime int: Interrupt) RawHandler {
    var code: []const u8 = if (int.has_error_code()) "" else "pushq $0\n";
    code = code ++ std.fmt.comptimePrint("pushq ${d}\n", .{@intFromEnum(int)});
    code = code ++ "jmp __isr_common\n";
    const c = code;
    return struct {
        fn handler() callconv(.Naked) void {
            asm volatile (c);
        }
    }.handler;
}

const raw_handlers: [256]RawHandler = blk: {
    var result: [256]RawHandler = undefined;
    for (0..256) |i| {
        result[i] = make_handler(@enumFromInt(i));
    }
    break :blk result;
};

pub fn add_handler(int: Interrupt, handler: InterruptHandler, typ: GateType, dpl: u2, ist: u3) void {
    idt[@intFromEnum(int)] = InterruptGateDescriptor.init(@intFromPtr(&raw_handlers[@intFromEnum(int)]), ist, typ, dpl);
    __isrs[@intFromEnum(int)] = handler;
}

pub fn clear() void {
    @memset(&idt, InterruptGateDescriptor.nul);
    const idtr = descriptors.TableRegister{
        .base = @intFromPtr(&idt),
        .limit = @sizeOf(idt),
    };
    asm volatile ("lidt %[p]"
        :
        : [p] "*p" (&idtr.limit),
    );
}

test {
    std.testing.refAllDecls(@This());
}
