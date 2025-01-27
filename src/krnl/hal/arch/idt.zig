const std = @import("std");
const descriptors = @import("descriptors.zig");
const gdt = @import("gdt.zig");
const arch = @import("arch.zig");

pub const GateType = enum(u4) {
    interrupt = 0xE,
    trap = 0xF,
    _,
};

pub const Exception = enum(u8) {
    divide_by_zero = 0x00,
    debug = 0x01,
    nmi = 0x02,
    breakpoint = 0x03,
    overflow = 0x04,
    bound_range_exceeded = 0x05,
    invalid_opcode = 0x06,
    device_not_available = 0x07,
    double_fault = 0x08,
    // coprocessor_segment_overrun = 0x09, // deprecated
    invalid_tss = 0x0A,
    segment_not_present = 0x0B,
    stack_segment_fault = 0x0C,
    general_protection_fault = 0x0D,
    page_fault = 0x0E,
    // 0x0F reserved
    x87_fp_exception = 0x10,
    alignment_check = 0x11,
    machine_check = 0x12,
    simd_fp_exception = 0x13,
    virtualization_exception = 0x14,
    control_protection_exception = 0x15,
    // 0x16 - 0x1B reserved
    hypervisor_injection_exception = 0x1C,
    vmm_communication_exception = 0x1D,
    security = 0x1E,
    _,
};

pub const Interrupt = packed union {
    exception: Exception,
    vector: @import("../hal.zig").InterruptVector,
    int: u8,

    pub fn has_error_code(self: Interrupt) bool {
        return switch (self.exception) {
            .double_fault, .invalid_tss, .segment_not_present, .general_protection_fault, .page_fault, .security => true,
            else => false,
        };
    }

    pub fn is_exception(self: Interrupt) bool {
        return self.int < 0x20;
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

    pub fn set_addr(desc: *InterruptGateDescriptor, addr: usize) void {
        desc.offset_low = @truncate(addr);
        desc.offset_upper = @truncate(addr >> 16);
    }

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

    pub const nul: InterruptGateDescriptor = .{
        .offset_low = 0,
        .segment_selector = gdt.selectors.null_desc,
        .ist = 0,
        .type = .interrupt,
        .dpl = 0,
        .present = false,
        .offset_upper = 0,
    };
};

const RawHandler = *const fn () callconv(.naked) void;
const InterruptHandler = *const fn (*RawInterruptFrame) callconv(arch.cc) void;

pub const SelectorIndexCode = packed struct(u64) {
    pub const Entry = union(enum) {
        interrupt: Interrupt,
        global_segment: gdt.Segment,
        local_segment: u13,
    };

    external: bool,
    interrupt: bool,
    entry: packed union {
        interrupt: packed struct(u14) {
            _: u1 = 0,
            index: u13,
        },
        segment: packed struct(u14) {
            table: enum(u1) {
                gdt = 0,
                ldt = 1,
            },
            index: u13,
        },
    },
    _: u48 = 0,

    pub fn target(self: SelectorIndexCode) Entry {
        if (self.interrupt) {
            return .{ .interrupt = @enumFromInt(self.entry.interrupt.index) };
        } else {
            switch (self.entry.segment.table) {
                .gdt => return .{ .global_segment = @enumFromInt(self.entry.segment.index) },
                .ldt => return .{ .local_segment = self.entry.segment.index },
            }
        }
    }
};

const crs = @import("ctrl_registers.zig").ControlRegisterValueType;

pub const SavedRegisters = extern struct {
    // NOTE the registers are in reverse order because of how stack pushing works
    // NOTE the asm to push and pop registers as part of the common isr block is
    //    generated at comptime based on reflection of this struct. the name of
    //    any field in this struct MUST match a valid register for an instruction of
    //    the form `pushq %reg`. any other information that needs to be saved in the
    //    isr should be put in InterruptFrame instead and the saving asm manually written
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rdi: u64,
    rsi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
};

const RawInterruptFrame = InterruptFrame(u64);

pub fn InterruptFrame(ErrorCode: type) type {
    return extern struct {
        gs_base: usize,
        fs_base: usize,
        cr4: crs(.cr4),
        cr3: crs(.cr3),
        cr2: crs(.cr2),
        cr0: crs(.cr0),
        registers: SavedRegisters align(8),
        vector: Interrupt align(8),
        error_code: ErrorCode,
        rip: usize,
        cs: descriptors.Selector align(8),
        eflags: @import("arch.zig").Flags,
        rsp: usize,
        ss: descriptors.Selector align(8),

        pub fn format(self: *const @This(), comptime _: []const u8, _: std.fmt.FormatOptions, fmt: anytype) !void {
            try fmt.print(
                \\v={x:0>2} e={x:0>16} cpl={d}
                \\     rax={x:16} rbx={x:16} rcx={x:16} rdx={x:16}
                \\     rsi={x:16} rdi={x:16} rbp={x:16} rsp={x:16}
                \\     r08={x:16} r09={x:16} r10={x:16} r11={x:16}
                \\     r12={x:16} r13={x:16} r14={x:16} r15={x:16}
                \\     rip={x:16}                                           flg={x:16}
                \\     cr0={x:0>8}         cr2={x:0>16} cr3={x:0>16} cr4={x:0>8}
                \\  fsbase={x:16}                   gsbase={x:16}
            , .{
                @as(u8, @bitCast(self.vector)),
                self.error_code,
                self.cs.rpl,
                self.registers.rax,
                self.registers.rbx,
                self.registers.rcx,
                self.registers.rdx,
                self.registers.rsi,
                self.registers.rdi,
                self.registers.rbp,
                self.rsp,
                self.registers.r8,
                self.registers.r9,
                self.registers.r10,
                self.registers.r11,
                self.registers.r12,
                self.registers.r13,
                self.registers.r14,
                self.registers.r15,
                self.rip,
                @as(u64, @bitCast(self.eflags)),
                @as(u64, @bitCast(self.cr0)),
                @as(u64, @bitCast(self.cr2)),
                @as(u64, @bitCast(self.cr3)),
                @as(u64, @bitCast(self.cr4)),
                self.fs_base,
                self.gs_base,
            });
        }
    };
}

pub noinline fn spoof_isr(isr: InterruptHandler) void {
    __isr__spoof__(isr, @returnAddress());
}

extern fn __isr__spoof__(isr: InterruptHandler, return_address: usize) callconv(arch.cc) void;

comptime {
    // the asm snippet of push operations for saved registers
    var push: []const u8 = "\n";
    // and the pops
    var pop: []const u8 = "\n";

    for (@typeInfo(SavedRegisters).@"struct".fields) |reg| {
        // prepend to push and append to pop - earlier fields in the struct must be pushed later so prepend
        // matches the semantics required due to the stack pushing downward
        push = "\n     pushq     %" ++ reg.name ++ push;
        // and append to pop since it must reverse the push order
        pop = pop ++ "     popq      %" ++ reg.name ++ "\n";
    }

    const isr_setup: []const u8 = push ++ // push all the saved registers
        \\      mov     %cr0, %rax # and the control registers
        \\      pushq   %rax
        \\      mov     %cr2, %rax
        \\      pushq   %rax
        \\      mov     %cr3, %rax
        \\      pushq   %rax
        \\      mov     %cr4, %rax
        \\      pushq   %rax
        \\      movq    $0xC0000100, %rcx # push FS_BASE
        \\      rdmsr
        \\      pushq   %rax
        \\      movl    %edx, 4(%rsp)
        \\      movq    $0xC0000101, %rcx # push GS_BASE
        \\      rdmsr
        \\      pushq   %rax
        \\      movl    %edx, 4(%rsp)
    ++ "\n      testb   $1, " ++ std.fmt.comptimePrint("{d}", .{@offsetOf(RawInterruptFrame, "cs")}) ++ "(%rsp)\n" ++
        \\      jz      1f
        \\      swapgs
        \\ 1:   cld
    ;

    const fake_isr: []const u8 =
        \\  .global __isr_spoof__;
        \\  .type __isr_spoof__, @function;
        \\  __isr__spoof__:
        \\      pushq   %rdi # push the handler address. this will be right above the frame
        \\      movq    %ss, %rdi
        \\      pushq   %rdi # normal interrupt frame things
        \\      movq    %rsp, %rdi
        \\      addq    $8, %rdi
        \\      pushq   %rdi
        \\      pushfq
        \\      movq    %cs, %rdi
        \\      pushq   %rdi
        \\      pushq   %rsi
        \\      pushq   $0 # no error code
        \\      pushq   $0x20 # use vector 0x20 to set the IRQL if the handler uses the normal bits
    ++ isr_setup
    // movq sizeOf(interrupt_frame)(%rsp), %rdx ; all the pushes we made will place the target handler to just above the frame
    ++ "\n      movq   " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(RawInterruptFrame)}) ++ "(%rsp), %rdx\n" ++
        \\      movq     %rsp, %rdi # rsp points to the bottom of the interrupt frame struct at this point so put that address in rdi
        \\      callq    *%rdx
        \\      jmp      __iret__
    ;

    const code: []const u8 =
        \\  .global __isr_common;
        \\  .type __isr_common, @function;
        \\  __isr_common:
    ++ isr_setup
    // movsbq offsetOf(vector)(%rsp), %rdx ; all the pushes we made will place rsp regscnt bytes below the intnum
    // which we need in rdx for the indexed callq below
    ++ "\n      movsbq   " ++ std.fmt.comptimePrint("{d}", .{@offsetOf(RawInterruptFrame, "vector")}) ++ "(%rsp), %rdx\n" ++
        \\      movq     %rsp, %rdi # rsp points to the bottom of the interrupt frame struct at this point so put that address in rdi
        \\      callq    *__isrs(, %rdx, 8)
        \\  .global __iret__;
        \\  .type __iret__, @function;
        \\  __iret__:
    ++ "\n      testb   $1, " ++ std.fmt.comptimePrint("{d}", .{@offsetOf(RawInterruptFrame, "cs")}) ++ "(%rsp)\n" ++
        \\      jz      2f
        \\      swapgs
        \\ 2:   cld
        \\      add      $48, %rsp # skip the control registers
    ++ pop ++ // pop all the saved normal registers
        \\      add      $8, %rsp
        \\      movl     4(%rsp), %edx # pop FS_BASE
        \\      popq     %rax
        \\      movq     $0xC0000100, %rcx
        \\      wrmsr
        \\      iretq    # and return from interrupt
    ;
    asm (fake_isr ++ "\n" ++ code);
}

export var idt: [256]InterruptGateDescriptor = undefined;
pub export var __isrs: [256]InterruptHandler = undefined;

fn make_handler(comptime int: Interrupt) RawHandler {
    // if the interrupt has an error code then that code is on top of the stack.
    // to make the frame size consistent we push 0 if there is no error code
    var code: []const u8 = if (int.has_error_code()) "" else "pushq $0\n";
    // push the error code
    code = code ++ std.fmt.comptimePrint("pushq ${d}\n", .{int.int});
    // and jump into __isr_common (defined above)
    code = code ++ "jmp __isr_common\n";
    // the string passed to asm has to be a comptime constant so just make a const here
    const c = code;
    // and anon function by way of anon struct
    return &struct {
        fn handler() callconv(.Naked) void {
            asm volatile (c);
        }
        comptime {
            // idk if this is strictly required but i was having a bit of a panic not being able to find the dang thing
            // in the disassembly, and at least with this i can confirm it works
            @export(&handler, .{ .name = std.fmt.comptimePrint("__isr_{x:0>2}", .{@as(u8, @bitCast(int))}), .linkage = .strong });
        }
    }.handler;
}

// make 256 raw handlers here, one per vector
// these are not put into the IDT immediately, instead we address them as needed when adding handlers
pub const raw_handlers: [256]RawHandler = blk: {
    var result: [256]RawHandler = undefined;
    for (0..256) |i| {
        result[i] = make_handler(.{ .int = i });
    }
    break :blk result;
};

var vectors: std.StaticBitSet(256) = blk: {
    var v1 = std.StaticBitSet(256).initEmpty();
    v1.setRangeValue(.{ .start = 0x0, .end = 0x1F }, true);
    v1.setRangeValue(.{ .start = 0xFE, .end = 0xFF }, true);
    break :blk v1;
};

pub fn is_vector_free(vector: u8) bool {
    return !vectors.isSet(vector);
}

const hal = @import("../hal.zig");
const InterruptRequestPriority = hal.InterruptRequestPriority;
const SpinLock = hal.SpinLock;
const InterruptVector = hal.InterruptVector;

var lasts: [14]u8 = .{0} ** 14;
var vectors_lock: SpinLock = .{};
pub noinline fn allocate_vector(level: InterruptRequestPriority) !InterruptVector {
    if (level == .passive) {
        return error.cannot_allocate_passive_interrupt;
    }
    const idx = @intFromEnum(level) - 2;
    const r = vectors_lock.lock();
    defer vectors_lock.unlock(r);

    while (lasts[idx] < 0x10) {
        const l: u4 = @truncate(@atomicRmw(u8, &lasts[idx], .Add, 1, .acq_rel));
        const v: InterruptVector = .{ .vector = l, .level = level };
        if (is_vector_free(@bitCast(v))) {
            return v;
        }
    }
    return error.OutOfVectors;
}

pub noinline fn allocate_vector_any(min: InterruptRequestPriority) !InterruptVector {
    for (@intFromEnum(min)..16) |irql| {
        return allocate_vector(@enumFromInt(irql)) catch continue;
    }
    return error.OutOfVectors;
}

/// handler can be a pointer to any function which takes *InterruptFrame(SomeErrorCodeType) as its only parameter
pub noinline fn add_handler(int: Interrupt, handler: anytype, typ: GateType, dpl: u2, ist: u3) void {
    // put a descriptor in the IDT pointing to the raw handler for the specified vector
    var descriptor = idt[int.int];
    descriptor.ist = ist;
    descriptor.dpl = dpl;
    descriptor.type = typ;
    idt[int.int] = descriptor;

    // and put the managed isr into the function pointer array so __isr_common calls into it
    __isrs[int.int] = @ptrCast(handler);
    vectors.set(int.int);
}

/// disable maskable interrupts
pub inline fn disable() void {
    asm volatile ("cli");
}

/// enable maskable interrupts
pub inline fn enable() void {
    asm volatile ("sti");
}

pub fn clear(unhandled_handler: anytype) void {
    for (0..256) |i| {
        idt[i] = InterruptGateDescriptor.init(@intFromPtr(raw_handlers[i]), 0, .interrupt, 0);
    }
    @memset(&__isrs, @ptrCast(unhandled_handler));
}

pub fn load() void {
    const idtr = descriptors.TableRegister{
        .base = @intFromPtr(&idt),
        .limit = @sizeOf(@TypeOf(idt)),
    };
    asm volatile ("lidt %[p]"
        :
        : [p] "*p" (&idtr.limit),
    );
}

pub fn get_and_disable() arch.Flags {
    const f = arch.flags();
    disable();
    return f;
}

pub fn restore(state: arch.Flags) void {
    arch.setflags(state);
}

test {
    std.testing.refAllDecls(@This());
}
