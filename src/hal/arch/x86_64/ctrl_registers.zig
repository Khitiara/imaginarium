pub const ControlRegister = enum {
    cr0,
    cr2,
    cr3,
    cr4,
    cr8,
};

pub fn ControlRegisterValueType(comptime cr: ControlRegister) type {
    switch (cr) {
        .cr0 => return packed struct(u64) {
            pe: bool,
            mp: bool,
            em: bool,
            ts: bool,
            et: bool,
            ne: bool,
            _reserved1: u10 = 0,
            wp: bool,
            _reserved2: u1 = 0,
            am: bool,
            _reserved3: u10 = 0,
            nw: bool,
            cd: bool,
            pg: bool,
            _reserved4: u32 = 0,
        },
        .cr2 => u64,
        .cr3 => packed struct(u64) {
            pcid: packed union {
                nopcid: packed struct(u12) {
                    _reserved1: u3 = 0,
                    pwt: bool,
                    pcd: bool,
                    _reserved2: u7 = 0,
                },
                pcid: u11,
            },
            pml45_base_addr: u52,

            // paging support functions
            pub fn get_phys_addr(self: @This()) u64 {
                return @as(u64, self.pml45_base_addr) << 12;
            }
            pub fn set_phys_addr(self: *@This(), addr: u64) void {
                self.pml45_base_addr = @truncate(addr >> 12);
            }
        },
        .cr4 => packed struct(u64) {
            vme: bool,
            pvi: bool,
            tsd: bool,
            de: bool,
            pse: bool,
            pae: bool,
            mce: bool,
            pge: bool,
            pce: bool,
            osfxsr: bool,
            osxmmexcpt: bool,
            umip: bool,
            _reserved1: u1 = 0,
            vmxe: bool,
            smxe: bool,
            _reserved2: u1 = 0,
            fsgsbase: bool,
            pcide: bool,
            osxsave: bool,
            _reserved3: u1 = 0,
            smep: bool,
            smap: bool,
            pke: bool,
            cet: bool,
            pks: bool,
            _reserved4: u39 = 0,
        },
        .cr8 => packed struct(u64) {
            tpr: u4,
            _reserved: u60 = 0,
        },
    }
}

pub inline fn read(comptime cr: ControlRegister) ControlRegisterValueType(cr) {
    return asm volatile ("movq %%" ++ @tagName(cr) ++ ", %[out]"
        : [out] "=r" (-> ControlRegisterValueType(cr)),
    );
}

pub inline fn write(comptime cr: ControlRegister, val: ControlRegisterValueType(cr)) void {
    asm volatile ("movq %[in], %%" ++ @tagName(cr)
        :
        : [in] "r" (val),
    );
}
