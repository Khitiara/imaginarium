// THIS FILE ALONE IS LICENSED UNDER THE BSD 0-CLAUSE LICENSE
//
// Zero-Clause BSD
// =============
//
// Permission to use, copy, modify, and/or distribute this software for
// any purpose with or without fee is hereby granted.
//
// THE SOFTWARE IS PROVIDED “AS IS” AND THE AUTHOR DISCLAIMS ALL
// WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
// OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE
// FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY
// DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
// AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
// OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

const std = @import("std");
const math = std.math;
const meta = std.meta;
const builtin = std.builtin;
const mem = std.mem;

const assert = std.debug.assert;

pub fn MultiBoundedArray(comptime T: type, comptime buffer_capacity: usize) type {
    return MultiBoundedArrayAligned(T, @alignOf(T), buffer_capacity);
}

pub fn MultiBoundedArrayAligned(
    comptime T: type,
    comptime alignment: u29,
    comptime buffer_capacity: usize,
) type {
    return struct {
        const Self = @This();
        const Len = math.IntFittingRange(0, buffer_capacity);

        const Elem = switch (@typeInfo(T)) {
            .@"struct" => T,
            .@"union" => |u| struct {
                pub const Bare =
                    @Type(.{ .Union = .{
                    .layout = u.layout,
                    .tag_type = null,
                    .fields = u.fields,
                    .decls = &.{},
                } });
                pub const Tag =
                    u.tag_type orelse @compileError("MultiArrayList does not support untagged unions");
                tags: Tag,
                data: Bare,

                pub fn fromT(outer: T) @This() {
                    const tag = meta.activeTag(outer);
                    return .{
                        .tags = tag,
                        .data = switch (tag) {
                            inline else => |t| @unionInit(Bare, @tagName(t), @field(outer, @tagName(t))),
                        },
                    };
                }
                pub fn toT(tag: Tag, bare: Bare) T {
                    return switch (tag) {
                        inline else => |t| @unionInit(T, @tagName(t), @field(bare, @tagName(t))),
                    };
                }
            },
            else => @compileError("MultiArrayList only supports structs and tagged unions"),
        };

        pub const Field = meta.FieldEnum(Elem);
        const fields: []const builtin.Type.StructField = meta.fields(Elem);

        pub const capacity: Len = buffer_capacity;

        const Buffers = blk: {
            var flds: [fields.len]builtin.Type.StructField = undefined;
            for (fields, 0..) |f, i| {
                flds[i] = .{
                    .name = f.name,
                    .type = [capacity]f.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = alignment,
                };
            }
            break :blk @Type(.{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &flds,
                    .is_tuple = false,
                    .decls = &.{},
                },
            });
        };

        bufs: Buffers = undefined,
        len: Len = 0,

        pub fn init(len: Len) error{Overflow}!Self {
            if (len > capacity) return error.Overflow;
            return .{
                .len = len,
            };
        }

        pub fn resize(self: *Self, new_len: Len) error{Overflow}!void {
            if (new_len > capacity) return error.Overflow;
            self.len = new_len;
        }

        pub fn items(self: *Self, comptime field: Field) []meta.FieldType(Elem, field) {
            const F = meta.FieldType(Elem, field);
            if (buffer_capacity == 0) {
                return &[_]F{};
            }
            return (&@field(self.bufs, @tagName(field)))[0..self.len];
        }

        pub fn set(self: *Self, index: Len, elem: T) void {
            const e = switch (@typeInfo(T)) {
                .@"struct" => elem,
                .@"union" => Elem.fromT(elem),
                else => unreachable,
            };
            inline for (fields, 0..) |field_info, i| {
                self.items(@as(Field, @enumFromInt(i)))[index] = @field(e, field_info.name);
            }
        }

        pub fn get(self: *const Self, index: Len) T {
            var result: Elem = undefined;
            inline for (fields, 0..) |field_info, i| {
                @field(result, field_info.name) = self.items(@as(Field, @enumFromInt(i)))[index];
            }
            return switch (@typeInfo(T)) {
                .Struct => result,
                .Union => Elem.toT(result.tags, result.data),
                else => unreachable,
            };
        }

        /// Inserts an item into an ordered list which has room for it.
        /// Shifts all elements after and including the specified index
        /// back by one and sets the given index to the specified element.
        /// Will not reallocate the array, does not invalidate iterators.
        pub fn insert(self: *Self, index: Len, elem: T) void {
            assert(self.len < capacity);
            assert(index <= self.len);
            self.len += 1;
            const entry = switch (@typeInfo(T)) {
                .Struct => elem,
                .Union => Elem.fromT(elem),
                else => unreachable,
            };
            inline for (fields, 0..) |field_info, field_index| {
                const field_slice = self.items(@as(Field, @enumFromInt(field_index)));
                var i: usize = self.len - 1;
                while (i > index) : (i -= 1) {
                    field_slice[i] = field_slice[i - 1];
                }
                field_slice[index] = @field(entry, field_info.name);
            }
        }

        /// Extend the list by 1 element, asserting `self.capacity`
        /// is sufficient to hold an additional item. Returns the
        /// newly reserved index with uninitialized data.
        pub fn add_one(self: *Self) error{Overflow}!Len {
            assert(self.len < capacity);
            return @atomicRmw(Len, &self.len, .Add, 1, .monotonic);
        }

        /// Extend the list by 1 element, asserting `self.capacity`
        /// is sufficient to hold an additional item. Returns the
        /// newly reserved index with initialized data.
        pub fn append(self: *Self, elem: T) error{Overflow}!Len {
            const idx = try self.add_one();
            self.set(idx, elem);
            return idx;
        }

        /// Remove the specified item from the list, swapping the last
        /// item in the list into its position.  Fast, but does not
        /// retain list ordering.
        pub fn swapRemove(self: *Self, index: Len) void {
            inline for (fields, 0..) |_, i| {
                const field_slice = self.items(@as(Field, @enumFromInt(i)));
                field_slice[index] = field_slice[self.len - 1];
                field_slice[self.len - 1] = undefined;
            }
            self.len -= 1;
        }

        /// Remove the specified item from the list, shifting items
        /// after it to preserve order.
        pub fn orderedRemove(self: *Self, index: Len) void {
            inline for (fields, 0..) |_, field_index| {
                const field_slice = self.items(@as(Field, @enumFromInt(field_index)));
                var i = index;
                while (i < self.len - 1) : (i += 1) {
                    field_slice[i] = field_slice[i + 1];
                }
                field_slice[i] = undefined;
            }
            self.len -= 1;
        }

        /// Remove and return the last element from the list.
        /// Asserts the list has at least one item.
        /// Invalidates pointers to fields of the removed element.
        pub fn pop(self: *Self) T {
            const val = self.get(self.len - 1);
            self.len -= 1;
            return val;
        }

        /// Remove and return the last element from the list, or
        /// return `null` if list is empty.
        /// Invalidates pointers to fields of the removed element, if any.
        pub fn popOrNull(self: *Self) ?T {
            if (self.len == 0) return null;
            return self.pop();
        }
    };
}
