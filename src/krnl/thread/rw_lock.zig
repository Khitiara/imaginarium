pub const RWLock = packed struct(u64) {
    locked: bool,
    waiting: bool,
    waking: bool,
    multiple_shared: bool,
    share_count_or_ptr: u60,
};
