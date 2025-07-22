const std = @import("std");
const atomic = std.atomic;

const MultiArray = @import("util").MultiArray;

/// A lockless log ring, inspired by linux kprintf.
///
/// The log ring consists of three internal ring buffers:
///   - a descriptor/metadata ring
///   - a data ring
///   - an info ring
///
/// Descriptor Ring:
/// A descriptor tracks the ID/SeqNum and state of a log entry, along with the start and end logical positions of
/// its associated data within the Data Ring. The bitwise ID/state field of a descriptor MUST only be accessed
/// atomically. The descriptor state enum is stored in the upper 2 bits of the ID/state field, and can take three
/// values:
///   - reserved: a writer has reserved this entry for writing
///   - finalized: writing has finished and this entry is readable
///   - reusable: this entry is in an invalid state and may be reserved
/// In addition to the array of entries, the descriptor ring tracks the sequence number of the head and tail entries
/// and the sequence number of the last finalized entry.
///
/// Data Ring:
/// Contains the raw binary data for each log message, usually text. Entries consist of a single u64 descriptor id
/// encoded in native byte order followed by the raw message data. The start and end indices of data within the data
/// ring are stored in the descriptor ring. All data blocks are naturally aligned for the descriptor id. Because the
/// descriptor id is naturally aligned in the data ring, the lower bits of a data ring index are used to flag entries
/// which have no/invalid data or whose data consists of an empty string (to be rendered out as an empty line)
///
/// Info Ring(s):
/// Contains metadata on log entries, stored separate from descriptors as the metadata isnt as often needed to access
/// so for compactness and cache efficiency it is stored separately. Additionally, the info ring is stored using
/// MultiArray (a fixed length version of MultiArrayList)
///
///
///
pub fn LogRing(comptime Seq: type, comptime entry_count_shift: comptime_int, comptime text_per_entry_shift: comptime_int) type {
    return struct {
        pub const entry_count_bits: usize = entry_count_shift;
        pub const text_per_entry_bits: usize = text_per_entry_shift;

        const SmallSeq = std.meta.Int(.unsigned, @bitSizeOf(Seq) - 2);

        pub const entries: SmallSeq = 1 << entry_count_shift;
        pub const text_size: usize = 1 << (entry_count_shift + text_per_entry_bits);

        const AtomicSeq = atomic.Value(Seq);

        pub const DataPos = struct {
            begin: u32,
            end: u32,

            pub const invalid: DataPos = .{
                .begin = 1,
                .end = 1,
            };
        };

        pub const DescriptorSeq = packed union {
            raw: Seq,
            pack: packed struct(Seq) {
                id: SmallSeq,
                state: enum(u2) {
                    reserved,
                    committed,
                    _unused,
                    reusable,
                },
            },
        };

        pub const Descriptor = struct {
            id_state: AtomicSeq,
            pos: DataPos,
        };

        pub const Info = struct {
            seq: u64,
            ts: u64,
            text_len: u16,
            level: std.log.Level,
        };

        const Self = @This();

        pub const init: Self = .{
            .descs = .{
                .descs = (.{undefined} ** (entries - 1)) ++ .{Descriptor{
                    .id_state = .init((DescriptorSeq{ .pack = .{ .id = -%(entries + 1), .state = .reusable } }).raw),
                    .pos = .invalid,
                }},
                .infos = .{
                    .bufs = .{
                        .seq = .{-%entries} ++ (.{undefined} ** (entries - 2)) ++ .{0},
                        .ts = undefined,
                        .text_len = undefined,
                        .level = undefined,
                    },
                },
                .head_id = .init(-%(entries + 1)),
                .tail_id = .init(-%(entries + 1)),
                .last_finalized_seq = .init(0),
            },
            .data = .{
                .data = undefined,
                .head_datapos = .init(-%text_size),
                .tail_datapos = .init(-%text_size),
            },
        };

        data: struct {
            data: [text_size]u8 align(8),
            head_datapos: AtomicSeq,
            tail_datapos: AtomicSeq,
        },
        descs: struct {
            descs: [entries]Descriptor,
            infos: MultiArray(Info, entries),
            head_id: AtomicSeq,
            tail_id: AtomicSeq,
            last_finalized_seq: AtomicSeq,
        },
    };
}

pub const global_ring: LogRing(usize, 15, 5) = .init;
