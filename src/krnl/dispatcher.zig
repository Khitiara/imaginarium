pub const DispatcherObjectKind = enum(u7) {
    semaphore,
    thread,
    interrupt,
    _,
};

pub const DispatcherObjectKindAndLock = packed struct(u8) {
    kind: DispatcherObjectKind,
    lock: bool,
};

pub const DispatcherHeader = extern struct {
    kind: DispatcherObjectKind,
};
