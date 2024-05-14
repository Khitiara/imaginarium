const std = @import("std");
const descriptors = @import("descriptors.zig");
const gdt = @import("gdt.zig");
const x86_64 = @import("x86_64.zig");

pub const GateType = enum(u4) {
    interrupt = 0xE,
    trap = 0xF,
    _,
};

pub const Interrupt = enum(u8) {
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
    pub fn has_error_code(self: Interrupt) bool {
        return switch (self) {
            .double_fault, .invalid_tss, .segment_not_present, .general_protection_fault, .page_fault, .security => true,
            else => false,
        };
    }

    pub fn is_exception(self: Interrupt) bool {
        return @intFromEnum(self) < 0x20;
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

    pub const nul = .{
        .offset_low = 0,
        .segment_selector = gdt.selectors.null_desc,
        .ist = 0,
        .type = .interrupt,
        .dpl = 0,
        .present = false,
        .offset_upper = 0,
    };
};

const RawHandler = *const fn () callconv(.Naked) void;
const InterruptHandler = *const fn (*RawInterruptFrame) callconv(.Win64) void;

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
        cr4: crs(.cr4),
        cr3: crs(.cr3),
        cr2: crs(.cr2),
        cr0: crs(.cr0),
        fs: descriptors.Selector align(8),
        gs: descriptors.Selector align(8),
        registers: SavedRegisters align(8),
        interrupt_number: Interrupt align(8),
        error_code: ErrorCode,
        rip: usize,
        cs: descriptors.Selector align(8),
        eflags: @import("x86_64.zig").Flags,
        rsp: usize,
        ss: descriptors.Selector align(8),

        pub fn format(self: *const @This(), comptime _: []const u8, _: std.fmt.FormatOptions, fmt: anytype) !void {
            try fmt.print(
                \\v={x:0>2} e={x:0>16} cpl={d}
                \\  rax={x:16} rbx={x:16} rcx={x:16} rdx={x:16}
                \\  rsi={x:16} rdi={x:16} rbp={x:16} rsp={x:16}
                \\  r08={x:16} r09={x:16} r10={x:16} r11={x:16}
                \\  r12={x:16} r13={x:16} r14={x:16} r15={x:16}
                \\  rip={x:16}  fs={x:16}  gs={x:16} flg={x:16}
                \\  cr0={x:0>8}         cr2={x:0>16} cr3={x:0>16} cr4={x:0>8}
            , .{
                @intFromEnum(self.interrupt_number),
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
                @as(u16, @bitCast(self.fs)),
                @as(u16, @bitCast(self.gs)),
                @as(u64, @bitCast(self.eflags)),
                @as(u64, @bitCast(self.cr0)),
                @as(u64, @bitCast(self.cr2)),
                @as(u64, @bitCast(self.cr3)),
                @as(u64, @bitCast(self.cr4)),
            });
        }
    };
}

pub noinline fn spoof_isr(isr: InterruptHandler) void {
    __isr__spoof__(isr, @returnAddress());
}

extern fn __isr__spoof__(isr: InterruptHandler, return_address: usize) callconv(.Win64) void;

comptime {
    // the asm snippet of push operations for saved registers
    var push: []const u8 = "\n";
    // and the pops
    var pop: []const u8 = "\n";

    for (@typeInfo(SavedRegisters).Struct.fields) |reg| {
        // prepend to push and append to pop - earlier fields in the struct must be pushed later so prepend
        // matches the semantics required due to the stack pushing downward
        push = "\n    pushq     %" ++ reg.name ++ push;
        // and append to pop since it must reverse the push order
        pop = pop ++ "    popq      %" ++ reg.name ++ "\n";
        // each register is 8 bytes so we add 8 here
    }

    const isr_setup: []const u8 = push ++ // push all the saved registers
        \\     mov      %gs, %rax # push the fs and gs segment selectors
        \\     pushq    %rax
        \\     mov      %fs, %rax
        \\     pushq    %rax
        \\     mov      %cr0, %rax # and the control registers
        \\     pushq    %rax
        \\     mov      %cr2, %rax
        \\     pushq    %rax
        \\     mov      %cr3, %rax
        \\     pushq    %rax
        \\     mov      %cr4, %rax
        \\     pushq    %rax
        \\     swapgs   # we saved the gs register selector so its safe to swap in the kernel gs base
    ;

    const fake_isr: []const u8 =
        \\ .global __isr_spoof__;
        \\ .type __isr_spoof__, @function;
        \\ __isr__spoof__:
        \\     pushq    %rcx # push the handler address. this will be right above the frame
        \\     movq     %ss, %rcx
        \\     pushq    %rcx # normal interrupt frame things
        \\     movq     %rsp, %rcx
        \\     addq     $8, %rcx
        \\     pushq    %rcx
        \\     pushfq
        \\     movq     %cs, %rcx
        \\     pushq    %rcx
        \\     pushq    %rdx
        \\     pushq    $0 # no error code
        \\     pushq    $0x20 # use vector 0x20 to set the IRQL if the handler uses the normal bits
    ++ isr_setup
    // movq sizeOf(interrupt_frame)(%rsp), %rdx ; all the pushes we made will place the target handler to just above the frame
    ++ "\n     movq   " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(RawInterruptFrame)}) ++ "(%rsp), %rdx\n" ++
        \\     movq     %rsp, %rcx # rsp points to the bottom of the interrupt frame struct at this point so put that address in rcx
        \\     callq    *%rdx
        \\     jmp      __iret__
    ;

    const code: []const u8 =
        \\ .global __isr_common;
        \\ .type __isr_common, @function;
        \\ __isr_common:
    ++ isr_setup
    // movsbq offsetOf(interrupt_number)(%rsp), %rdx ; all the pushes we made will place rsp regscnt bytes below the intnum
    // which we need in rdx for the indexed callq below
    ++ "\n     movsbq   " ++ std.fmt.comptimePrint("{d}", .{@offsetOf(RawInterruptFrame, "interrupt_number")}) ++ "(%rsp), %rdx\n" ++
        \\     movq     %rsp, %rcx # rsp points to the bottom of the interrupt frame struct at this point so put that address in rcx
        \\     callq    *__isrs(, %rdx, 8)
        \\ .global __iret__;
        \\ .type __iret__, @function;
        \\ __iret__:
        \\     swapgs   # and swap back out the kernel gs so we dont override it
        \\     add      $32, %rsp # skip the control registers
        \\     popq     %rax # pop fs and gs segment selectors
        \\     mov      %rax, %fs
        \\     popq     %rax
        \\     mov      %rax, %gs
    ++ pop ++ // pop all the saved registers
        \\     add      $16, %rsp
        \\     iretq    # and return from interrupt
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
    code = code ++ std.fmt.comptimePrint("pushq ${d}\n", .{@intFromEnum(int)});
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
            @export(handler, .{ .name = std.fmt.comptimePrint("__isr_{x:0>2}", .{@intFromEnum(int)}), .linkage = .strong });
        }
    }.handler;
}

// make 256 raw handlers here, one per vector
// these are not put into the IDT immediately, instead we address them as needed when adding handlers
pub const raw_handlers: [256]RawHandler = blk: {
    var result: [256]RawHandler = undefined;
    for (0..256) |i| {
        result[i] = make_handler(@enumFromInt(i));
    }
    break :blk result;
};

var vectors = blk: {
    var v1 = std.StaticBitSet(256).initEmpty();
    v1.setRangeValue(.{.start = 0x0, .end = 0x1F}, true);
    v1.setRangeValue(.{.start = 0xFE, .end = 0xFF}, true);
    break :blk v1;
};

pub fn is_vector_free(vector: u8) bool {
    return !vectors.isSet(vector);
}

/// handler can be a pointer to any function which takes *InterruptFrame(SomeErrorCodeType) as its only parameter
pub fn add_handler(int: Interrupt, handler: anytype, typ: GateType, dpl: u2, ist: u3) void {
    // put a descriptor in the IDT pointing to the raw handler for the specified vector
    idt[@intFromEnum(int)] = InterruptGateDescriptor.init(@intFromPtr(raw_handlers[@intFromEnum(int)]), ist, typ, dpl);
    // and put the managed isr into the function pointer array so __isr_common calls into it
    __isrs[@intFromEnum(int)] = @ptrCast(handler);
    vectors.set(@intFromEnum(int));
}

/// disable maskable interrupts
pub inline fn disable() void {
    asm volatile ("cli");
}

/// enable maskable interrupts
pub inline fn enable() void {
    asm volatile ("sti");
}

pub fn clear() void {
    @memset(&idt, InterruptGateDescriptor.nul);
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

pub fn get_and_disable() bool {
    const f = x86_64.flags().interrupt_enable;
    disable();
    return f;
}

pub fn restore(state: bool) void {
    if (state) {
        enable();
    } else {
        disable();
    }
}

test {
    std.testing.refAllDecls(@This());
}
