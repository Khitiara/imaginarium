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

//! a selection of intrusive collections
//! these implementations are derived from N00byEdge's work in
//! https://github.com/FlorenceOS/Florence/blob/aaa5a9e568197ad24780ec9adb421217530d4466/lib/containers/queue.zig
//! which was released under the BSD 0-clause

const std = @import("std");
const CopyPtrAttrs = @import("util.zig").CopyPtrAttrs;

pub const Node = extern struct {
    next: ?*Node = null,
};

pub const UntypedQueue = struct {
    head: ?*Node = null,
    tail: ?*Node = null,
    len: usize = 0,

    pub fn append(self: *UntypedQueue, hook: *Node) void {
        hook.next = null;

        if (self.tail) |tail| {
            tail.next = hook;
            self.tail = hook;
        } else {
            std.debug.assert(self.head == null);
            self.head = hook;
            self.tail = hook;
        }

        self.len += 1;
    }

    pub fn prepend(self: *UntypedQueue, hook: *Node) void {
        hook.next = self.head;
        self.head = hook;

        self.len += 1;
    }

    pub fn peek(self: *const UntypedQueue) ?*Node {
        return self.head;
    }

    pub fn dequeue(self: *UntypedQueue) ?*Node {
        if (self.head) |head| {
            if (head.next) |next| {
                self.head = next;
            } else {
                self.head = null;
                self.tail = null;
            }

            self.len -= 1;
            return head;
        } else {
            return null;
        }
    }

    /// WARNING: THIS FUNCTION DOES NOT ENSURE REMOVED ITEMS ARE FREED. BE CAREFUL
    /// returns the old head for iteration and freeing
    pub fn clear(self: *UntypedQueue) ?*Node {
        defer {
            self.head = null;
            self.tail = null;
        }
        return self.head;
    }
};

pub fn Queue(comptime T: type, comptime field_name: []const u8) type {
    return struct {
        impl: UntypedQueue = .{},

        pub inline fn length(self: *const @This()) usize {
            return self.impl.len;
        }

        pub inline fn node_from_ref(ref: *T) *Node {
            return &@field(ref, field_name);
        }

        pub inline fn ref_from_node(node: *Node) *T {
            return @fieldParentPtr(field_name, node);
        }

        pub inline fn ref_from_optional_node(node: ?*Node) ?*T {
            return @fieldParentPtr(field_name, node orelse return null);
        }

        pub fn append(self: *@This(), item: *T) void {
            self.impl.append(node_from_ref(item));
        }

        pub fn prepend(self: *@This(), item: *T) void {
            self.impl.prepend(node_from_ref(item));
        }

        pub fn peek(self: *const @This()) ?*T {
            return if (self.impl.peek()) |head| ref_from_node(head) else null;
        }

        pub fn dequeue(self: *@This()) ?*T {
            if (self.impl.dequeue()) |node| {
                return ref_from_node(node);
            } else {
                return null;
            }
        }

        pub fn clear(self: *@This()) ?*T {
            return if (self.impl.clear()) |n| ref_from_node(n) else return null;
        }
    };
}

test "append" {
    const TestNode = struct {
        hook: Node = undefined,
        val: u64,
    };
    var queue: Queue(TestNode, "hook") = .{};
    var elems = [_]TestNode{
        .{ .val = 1 },
        .{ .val = 2 },
        .{ .val = 3 },
    };
    queue.append(&elems[0]);
    queue.append(&elems[1]);
    queue.append(&elems[2]);
    try std.testing.expectEqual(&elems[0], queue.dequeue());
    try std.testing.expectEqual(&elems[1], queue.dequeue());
    try std.testing.expectEqual(&elems[2], queue.dequeue());
    try std.testing.expectEqual(null, queue.dequeue());
}

test "prepend" {
    const TestNode = struct {
        hook: Node = undefined,
        val: u64,
    };
    var queue: Queue(TestNode, "hook") = .{};
    var elems = [_]TestNode{
        .{ .val = 1 },
        .{ .val = 2 },
        .{ .val = 3 },
    };
    queue.prepend(&elems[0]);
    queue.prepend(&elems[1]);
    queue.prepend(&elems[2]);
    try std.testing.expectEqual(&elems[2], queue.dequeue());
    try std.testing.expectEqual(&elems[1], queue.dequeue());
    try std.testing.expectEqual(&elems[0], queue.dequeue());
    try std.testing.expectEqual(null, queue.dequeue());
}

pub fn PriorityQueue(comptime T: type, comptime node_field_name: []const u8, comptime prio_field_name: []const u8, comptime P: type) type {
    const Tails = std.EnumArray(P, ?*Node);
    const Indexer = Tails.Indexer;
    return struct {
        head: ?*Node = null,
        tails: Tails = Tails.initFill(null),
        len: usize = 0,

        pub inline fn node_from_ref(ref: *T) *Node {
            return &@field(ref, node_field_name);
        }

        pub inline fn ref_from_node(node: *Node) *T {
            return @fieldParentPtr(node_field_name, node);
        }

        pub inline fn ref_from_optional_node(node: ?*Node) ?*T {
            return @fieldParentPtr(node_field_name, node orelse return null);
        }

        inline fn node_prio(node: *Node) P {
            return @field(ref_from_node(node).*, prio_field_name);
        }

        pub fn peek(self: *const @This()) ?*T {
            return if (self.head) |h| ref_from_node(h) else null;
        }

        pub fn add(self: *@This(), item: *T) void {
            const prio: P = @field(item.*, prio_field_name);
            const hook = node_from_ref(item);
            if (self.head) |head| {
                // iterate backwards to find the lowest tail with priority no lower than the new element
                // whose next will be set to the new element.
                // if such a tail doesnt exist then this element gets prepended as its a higher prio than everything
                // in the list so far
                var i = Indexer.indexOf(prio) + 1;
                while (std.math.sub(usize, i, 1)) |idx| {
                    i = idx;
                    // if the tail of the ith priority exists
                    if (self.tails.values[idx]) |tail| {
                        // stick this node on the end of that tail
                        hook.next = tail.next;
                        tail.next = hook;
                        break;
                    }
                } else |_| {
                    hook.next = head;
                    self.head = hook;
                }
            } else {
                hook.next = null;
                self.head = hook;
            }
            self.tails.getPtr(prio).* = hook;
            self.len += 1;
        }

        pub fn dequeue(self: *@This()) ?*T {
            if (self.head) |head| {
                const head_prio = node_prio(head);
                if (head == self.tails.get(head_prio)) {
                    self.tails.set(head_prio, null);
                }
                self.head = head.next;
                head.next = null;
                self.len -= 1;
                return ref_from_node(head);
            } else {
                return null;
            }
        }

        pub fn clear(self: *@This()) ?*T {
            defer {
                self.head = null;
                @memset(&self.tails.values, null);
            }

            return if (self.head) |h| ref_from_node(h) else null;
        }
    };
}

pub const DoublyLinkedNode = extern struct {
    next: ?*DoublyLinkedNode = null,
    prev: ?*DoublyLinkedNode = null,
};

pub const UntypedDoublyLinkedList = struct {
    head: ?*DoublyLinkedNode = null,
    tail: ?*DoublyLinkedNode = null,
    len: usize = 0,

    pub fn add_back(self: *UntypedDoublyLinkedList, n: *DoublyLinkedNode) void {
        self.len += 1;
        if (self.tail) |tail| {
            tail.next = n;
            self.tail = n;
            n.prev = tail;
            n.next = null;
        } else {
            self.head = n;
            self.tail = n;
            n.next = null;
            n.prev = null;
        }
    }

    pub fn add_front(self: *UntypedDoublyLinkedList, n: *DoublyLinkedNode) void {
        self.len += 1;
        if (self.head) |head| {
            n.next = head;
            n.prev = null;
            head.prev = n;
            self.head = n;
        } else {
            self.head = n;
            self.tail = n;
            n.next = null;
            n.prev = null;
        }
    }

    pub fn remove_front(self: *UntypedDoublyLinkedList) ?*Node {
        self.len -= 1;
        if (self.head) |head| {
            if (head.next) |n| {
                self.head = n;
                n.prev = null;
            } else {
                self.head = null;
                self.tail = null;
            }
            return head;
        } else {
            return null;
        }
    }

    pub fn remove_back(self: *UntypedDoublyLinkedList) ?*Node {
        self.len -= 1;
        if (self.tail) |tail| {
            if (tail.prev) |p| {
                self.tail = p;
                p.next = null;
            } else {
                self.head = null;
                self.tail = null;
            }
            return tail;
        } else {
            return null;
        }
    }

    pub fn remove(self: *UntypedDoublyLinkedList, n: *DoublyLinkedNode) void {
        self.len -= 1;
        if (n.next) |n2| {
            // has a next item, update next.prev
            n2.prev = n.prev;
        } else {
            // no next item therefore is the tail
            self.tail = n.prev;
        }
        if (n.prev) |p| {
            // has a prev item, update prev.next
            p.next = n.next;
        } else {
            // no prev item therefore is the head
            self.head = n.next;
        }
    }

    pub fn add_after(self: *UntypedDoublyLinkedList, n: *DoublyLinkedNode, i: *DoublyLinkedNode) void {
        self.len += 1;
        if (n.next) |n1| {
            i.next = n1;
            n1.prev = i;
        } else {
            i.next = null;
            self.tail = i;
        }
        n.next = i;
        i.prev = n;
    }

    pub fn add_before(self: *UntypedDoublyLinkedList, n: *DoublyLinkedNode, i: *DoublyLinkedNode) void {
        self.len += 1;
        if (n.prev) |p| {
            p.next = i;
            i.prev = p;
        } else {
            i.prev = null;
            self.head = i;
        }
        i.next = n;
        n.prev = i;
    }
};

pub fn DoublyLinkedList(comptime T: type, comptime field_name: []const u8) type {
    return struct {
        impl: UntypedDoublyLinkedList = .{},

        pub inline fn length(self: *const @This()) usize {
            return self.impl.len;
        }

        pub inline fn node_from_ref(ref: *T) *DoublyLinkedNode {
            return &@field(ref, field_name);
        }

        pub inline fn ref_from_node(node: *DoublyLinkedNode) *T {
            return @fieldParentPtr(field_name, node);
        }

        pub inline fn ref_from_optional_node(node: ?*DoublyLinkedNode) ?*T {
            return @fieldParentPtr(field_name, node orelse return null);
        }

        pub fn peek_front(self: *@This()) ?*T {
            return ref_from_optional_node(self.impl.head);
        }

        pub fn peek_back(self: *@This()) ?*T {
            return ref_from_optional_node(self.impl.tail);
        }

        pub fn add_back(self: *@This(), item: *T) void {
            self.impl.add_back(node_from_ref(item));
        }

        pub fn add_front(self: *@This(), item: *T) void {
            self.impl.add_front(node_from_ref(item));
        }

        pub fn add_before(self: *@This(), node: *T, item: *T) void {
            self.impl.add_before(node_from_ref(node), node_from_ref(item));
        }

        pub fn add_after(self: *@This(), node: *T, item: *T) void {
            self.impl.add_after(node_from_ref(node), node_from_ref(item));
        }

        pub fn remove(self: *@This(), item: *T) void {
            self.impl.remove(node_from_ref(item));
        }

        pub fn remove_front(self: *@This()) ?*T {
            return if (self.impl.remove_front()) |n| ref_from_node(n) else null;
        }

        pub fn remove_back(self: *@This()) ?*T {
            return if (self.impl.remove_back()) |n| ref_from_node(n) else null;
        }

        pub fn clear(self: *@This()) ?*T {
            return if (self.impl.clear()) |n| ref_from_node(n) else return null;
        }
    };
}
