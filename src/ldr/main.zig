const cmn = @import("cmn");
const types = cmn.types;
const bootelf = cmn.bootelf;

export fn __kstart2(ldr_info: *bootelf.BootelfData) callconv(types.cc) noreturn {
    _ = ldr_info;
    while (true) {}
}
