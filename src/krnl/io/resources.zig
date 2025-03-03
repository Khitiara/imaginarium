//! io device resources, reported to a higher level driver by a lower level driver.
//! resource types include io port ranges, memory address ranges, GSI or ISA interrupt numbers,
//! MSI(x) interrupts, dma, gpio pins, etc.
//!
//! generally, resources will be enumerated by a bus driver, with the most common mechanisms being
//! the ACPI _CRS method or PCI(e) BARs. higher level drivers will always report resources first,
//! and the order of resources is specific to the bus driver - e.g. the PCI(e) bus driver will always
//! report each BAR's mapping in order followed by any MSI(x) or other resources, and the ACPI bus
//! driver will always report resources in the order returned by the _CRS method.

const io = @import("io.zig");
const queue = @import("collections").queue;
const PhysAddr = @import("cmn").types.PhysAddr;

const apic = @import("../hal/apic/apic.zig");
const hal = @import("../hal/hal.zig");

pub const PortRange = struct {
    start: u16,
    len: u16,
};

pub const Resource = struct {
    _: union(enum) {
        ports: union(enum) {
            @"8": PortRange,
            @"16": PortRange,
            @"32": PortRange,
        },
        memory: struct {
            start: PhysAddr,
            length: usize,
        },
        interrupt: struct {
            irql: hal.InterruptRequestPriority,
            vector: u32,
        },
        msi: struct {
            irql: hal.InterruptRequestPriority,
            vector: u32,
            message_count: u4,
        },
        msix: struct {
            irql: hal.InterruptRequestPriority,
            vector: u8,
        },
    },
    hook: queue.SinglyLinkedNode,
};