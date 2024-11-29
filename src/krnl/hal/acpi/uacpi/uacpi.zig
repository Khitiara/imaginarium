pub const uacpi_object = opaque {};
pub const uacpi_handle = *anyopaque;

pub const namespace_node = opaque {};
pub const log_level = enum(u32) {
    err = 1,
    warn = 2,
    info = 3,
    trace = 4,
    debug = 5,
};
pub const uacpi_init_level = enum(u32) {
    early = 0,
    subsystem_initialized = 1,
    namespace_loaded = 2,
    namespace_initialized = 3,
};

pub const PciAddress = extern struct {
    segment: u16 = 0,
    bus: u8 = 0,
    device: u8 = 0,
    function: u8 = 0,
};

pub const IoAddress = enum(u64) { _ };

pub const Error = error{
    MappingFailed,
    OutOfMemory,
    BadChecksum,
    InvalidSignature,
    InvalidTableLength,
    NotFound,
    InvalidArgument,
    Unimplemented,
    AlreadyExists,
    InternalError,
    TypeMismatch,
    InitLevelMismatch,
    NamespaceNodeDangling,
    NoHandler,
    NoResourceEndTag,
    CompiledOut,
    HardwareTimeout,
    Timeout,
    Overridden,
    Denied,
    AmlUndefinedReference,
    AmlInvalidNamestring,
    AmlObjectAlreadyExists,
    AmlInvalidOpcode,
    AmlIncompatibleObjectType,
    AmlBadEncoding,
    AmlOutOfBoundsIndex,
    AmlSyncLevelTooHigh,
    AmlInvalidResource,
    AmlLoopTimeout,
    AmlCallStackDepthLimit,
};

pub const uacpi_status = enum(c_uint) {
    ok = 0,
    mapping_failed = 1,
    out_of_memory = 2,
    bad_checksum = 3,
    invalid_signature = 4,
    invalid_table_length = 5,
    not_found = 6,
    invalid_argument = 7,
    unimplemented = 8,
    already_exists = 9,
    internal_error = 10,
    type_mismatch = 11,
    init_level_mismatch = 12,
    namespace_node_dangling = 13,
    no_handler = 14,
    no_resource_end_tag = 15,
    compiled_out = 16,
    hardware_timeout = 17,
    timeout = 18,
    overridden = 19,
    denied = 20,
    aml_undefined_reference = 251592704,
    aml_invalid_namestring = 251592705,
    aml_object_already_exists = 251592706,
    aml_invalid_opcode = 251592707,
    aml_incompatible_object_type = 251592708,
    aml_bad_encoding = 251592709,
    aml_out_of_bounds_index = 251592710,
    aml_sync_level_too_high = 251592711,
    aml_invalid_resource = 251592712,
    aml_loop_timeout = 251592713,
    aml_call_stack_depth_limit = 251592714,
    _,

    pub inline fn err(s: uacpi_status) Error!void {
        return switch (s) {
            .ok => {},
            .mapping_failed => error.MappingFailed,
            .out_of_memory => error.OutOfMemory,
            .bad_checksum => error.BadChecksum,
            .invalid_signature => error.InvalidSignature,
            .invalid_table_length => error.InvalidTableLength,
            .not_found => error.NotFound,
            .invalid_argument => error.InvalidArgument,
            .unimplemented => error.Unimplemented,
            .already_exists => error.AlreadyExists,
            .internal_error => error.InternalError,
            .type_mismatch => error.TypeMismatch,
            .init_level_mismatch => error.InitLevelMismatch,
            .namespace_node_dangling => error.NamespaceNodeDangling,
            .no_handler => error.NoHandler,
            .no_resource_end_tag => error.NoResourceEndTag,
            .compiled_out => error.CompiledOut,
            .hardware_timeout => error.HardwareTimeout,
            .timeout => error.Timeout,
            .overridden => error.Overridden,
            .denied => error.Denied,
            .aml_undefined_reference => error.AmlUndefinedReference,
            .aml_invalid_namestring => error.AmlInvalidNamestring,
            .aml_object_already_exists => error.AmlObjectAlreadyExists,
            .aml_invalid_opcode => error.AmlInvalidOpcode,
            .aml_incompatible_object_type => error.AmlIncompatibleObjectType,
            .aml_bad_encoding => error.AmlBadEncoding,
            .aml_out_of_bounds_index => error.AmlOutOfBoundsIndex,
            .aml_sync_level_too_high => error.AmlSyncLevelTooHigh,
            .aml_invalid_resource => error.AmlInvalidResource,
            .aml_loop_timeout => error.AmlLoopTimeout,
            .aml_call_stack_depth_limit => error.AmlCallStackDepthLimit,
            else => @panic("Invalid UACPI error"),
        };
    }

    pub inline fn status(e: Error) uacpi_status {
        return switch (e) {
            error.MappingFailed => .mapping_failed,
            error.OutOfMemory => .out_of_memory,
            error.BadChecksum => .bad_checksum,
            error.InvalidSignature => .invalid_signature,
            error.InvalidTableLength => .invalid_table_length,
            error.NotFound => .not_found,
            error.InvalidArgument => .invalid_argument,
            error.Unimplemented => .unimplemented,
            error.AlreadyExists => .already_exists,
            error.InternalError => .internal_error,
            error.TypeMismatch => .type_mismatch,
            error.InitLevelMismatch => .init_level_mismatch,
            error.NamespaceNodeDangling => .namespace_node_dangling,
            error.NoHandler => .no_handler,
            error.NoResourceEndTag => .no_resource_end_tag,
            error.CompiledOut => .compiled_out,
            error.HardwareTimeout => .hardware_timeout,
            error.Timeout => .timeout,
            error.Overridden => .overridden,
            error.Denied => .denied,
            error.AmlUndefinedReference => .aml_undefined_reference,
            error.AmlInvalidNamestring => .aml_invalid_namestring,
            error.AmlObjectAlreadyExists => .aml_object_already_exists,
            error.AmlInvalidOpcode => .aml_invalid_opcode,
            error.AmlIncompatibleObjectType => .aml_incompatible_object_type,
            error.AmlBadEncoding => .aml_bad_encoding,
            error.AmlOutOfBoundsIndex => .aml_out_of_bounds_index,
            error.AmlSyncLevelTooHigh => .aml_sync_level_too_high,
            error.AmlInvalidResource => .aml_invalid_resource,
            error.AmlLoopTimeout => .aml_loop_timeout,
            error.AmlCallStackDepthLimit => .aml_call_stack_depth_limit,
        };
    }
};

extern fn uacpi_setup_early_table_access(temporary_buffer: [*]u8, buffer_size: usize) uacpi_status;
pub inline fn setup_early_table_access(temporary_buffer: []u8) Error!void {
    return uacpi_setup_early_table_access(temporary_buffer.ptr, temporary_buffer.len).err();
}

pub const uacpi_flags = packed struct(u64) {
    bad_csum_fatal: bool = false,
    bad_tbl_sig_fatal: bool = false,
    no_xsdt: bool = false,
    no_acpi_mode: bool = false,
    no_osi: bool = false,
    proactive_table_csum: bool = false,
    _: u58 = 0,
};
extern fn uacpi_initialize(flags: uacpi_flags) uacpi_status;
pub inline fn initialize(flags: uacpi_flags) Error!void {
    return uacpi_initialize(flags).err();
}

extern fn uacpi_namespace_load() uacpi_status;
pub inline fn namespace_load() Error!void {
    return uacpi_namespace_load().err();
}

extern fn uacpi_namespace_initialize() uacpi_status;
pub inline fn namespace_initialize() Error!void {
    return uacpi_namespace_initialize().err();
}

pub extern fn uacpi_get_current_init_level() uacpi_init_level;
extern fn uacpi_leave_acpi_mode() uacpi_status;
pub inline fn leave_acpi_mode() Error!void {
    return uacpi_leave_acpi_mode().err();
}

pub extern fn uacpi_state_reset() void;

pub extern fn uacpi_status_to_string(uacpi_status) [*:0]const u8;

pub const InterruptRet = enum(u32) {
    not_handled,
    handled,
};

pub const InterruptHandler = *const fn (?*anyopaque) callconv(.C)  InterruptRet;

pub const FirmwareRequestType = enum(u8) {
    breakpoint,
    fatal,
};

pub const FirmwareRequestRaw = extern struct {
    typ: FirmwareRequestType,
    data: extern union {
        breakpoint: extern struct {
            ctx: ?*anyopaque,
        },
        fatal: extern struct {
            typ: u8,
            code: u32,
            arg: u64,
        },
    },
};

pub const FirmwareRequest = union(FirmwareRequestType) {
    breakpoint: extern struct {
        ctx: ?*anyopaque,
    },
    fatal: extern struct {
        typ: u8,
        code: u32,
        arg: u64,
    },
};

pub const WorkType = enum(u32) {
    gpe_execution,
    notification,
};

pub const WorkHandler = *const fn(?*anyopaque) callconv(.C) void;