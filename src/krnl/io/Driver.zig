const ob = @import("../objects/ob.zig");
const util = @import("util");
const Device = @import("Device.zig");

header: ob.Object,
devices: util.queue.Queue(Device, "hook") = .{},
