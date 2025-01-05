//! intrusive AVL- (and eventually RB-) tree implementations
//! based on the use of `@fieldParentPtr` for simplified
//! implementation.
//!
//! released under the BSD 0-clause along with the rest of
//! the collections in this directory

const std = @import("std");
const CopyPtrAttrs = @import("util").CopyPtrAttrs;
const Order = std.math.Order;

/// a tree node for use in intrusive self-balancing trees.
///
/// THIS MUST HAVE AN ALIGNMENT OF AT LEAST 4 FOR SELF-BALANCING TREE SUPPORT ROUTINES
/// while this alignment is natural due to the 4- or 8-byte alignment of pointers on 32
/// and 64 bit platforms respectively, it is important that that alignment is never
/// overridden
pub const TreeNode = struct {
    left: ?*TreeNode = null,
    right: ?*TreeNode = null,
    parent_balance: packed union {
        parent: ?*TreeNode,
        rb: packed struct(usize) {
            color: enum(u1) {
                black = 0,
                red = 1,
            },
            _: std.meta.Int(.unsigned, @bitSizeOf(usize) - 1) = 0,
        },
        avl: packed struct(usize) {
            balance: i2,
            _: std.meta.Int(.unsigned, @bitSizeOf(usize) - 2) = 0,
        },
        int: usize,
        pub inline fn get_parent(self: *const @This()) ?*TreeNode {
            return @ptrFromInt(self.int & ~@as(usize, 3));
        }
        pub inline fn set_parent(self: *@This(), p: ?*TreeNode) void {
            self.* = .{ .int = (@intFromPtr(p) & ~@as(usize, 3)) | (self.int & 3) };
        }
    } = .{ .parent = null },
    pub inline fn get_parent(self: *const TreeNode) ?*TreeNode {
        return self.parent_balance.get_parent();
    }
    pub inline fn set_parent(self: *TreeNode, p: ?*TreeNode) void {
        self.parent_balance.set_parent(p);
    }
};

pub fn AvlTree(
    comptime T: type,
    comptime field_name: []const u8,
    /// A namespace that provides this one function:
    /// * `pub fn cmp(self, *const T, *const T) Order`
    comptime Context: type,
) type {
    return struct {
        inline fn cmp(ctx: Context, lhs: *const TreeNode, rhs: *const TreeNode) Order {
            return Context.cmp(ctx, ref_from_node(lhs), ref_from_node(rhs));
        }

        pub inline fn node_from_ref(ref: anytype) CopyPtrAttrs(@TypeOf(ref), .One, TreeNode) {
            if (@typeInfo(@TypeOf(ref)) == .optional) return node_from_optional_ref(ref);
            return &@field(ref, field_name);
        }

        pub inline fn node_from_optional_ref(ref: anytype) CopyPtrAttrs(@TypeOf(ref), .One, TreeNode) {
            return &@field(ref orelse return null, field_name);
        }

        pub inline fn ref_from_node(node: anytype) CopyPtrAttrs(@TypeOf(node), .One, T) {
            if (@typeInfo(@TypeOf(node)) == .optional) return ref_from_optional_node(node);
            return @fieldParentPtr(field_name, node);
        }

        pub inline fn ref_from_optional_node(node: anytype) ?CopyPtrAttrs(@typeInfo(@TypeOf(node)).optional.child, .One, T) {
            return @fieldParentPtr(field_name, node orelse return null);
        }

        pub inline fn lookup(root: *const ?*TreeNode, item: *const T) ?*T {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call lookup_context instead.");
            return lookup_context(root, item, undefined);
        }

        /// same as lookup_adapted but strongly typed
        pub inline fn lookup_context(root: *const ?*TreeNode, item: *const T, ctx: Context) ?*T {
            return lookup_adapted(root, item, ctx);
        }

        /// ctx must have a `fn cmp(self, @TypeOf(key), *const T) Order`
        pub fn lookup_adapted(root: *const ?*TreeNode, key: anytype, ctx: anytype) ?*T {
            var cur = root.*;
            while (cur) |c| {
                switch (ctx.cmp(key, ref_from_node(c))) {
                    .lt => cur = c.left,
                    .gt => cur = c.right,
                    .eq => break,
                }
            }
            return ref_from_optional_node(cur);
        }

        fn rebalance_after_insert(root: *?*TreeNode, item: *TreeNode) void {
            item.left = null;
            item.right = null;

            var node: *TreeNode = item;
            var parent: *TreeNode = item.get_parent() orelse return;

            parent.parent_balance.avl.balance += if (node == parent.left) -1 else 1;
            if (parent.parent_balance.avl.balance == 0) return;

            while (true) {
                node = parent;
                parent = node.get_parent() orelse return;

                if (if (node == parent.left) handle_subtree_growth(root, node, parent, -1) else handle_subtree_growth(root, node, parent, 1)) return;
            }
        }

        fn handle_subtree_growth(root: *?*TreeNode, item: *TreeNode, parent: *TreeNode, comptime sign: comptime_int) bool {
            const old_balance_factor: i32 = parent.parent_balance.avl.balance;
            if (old_balance_factor == 0) {
                parent.parent_balance.avl.balance += sign;
                // parent is sufficiently balanced but height increased; continue up
                return false;
            }
            const new_balance_factor = old_balance_factor + sign;
            if (new_balance_factor == 0) {
                parent.parent_balance.avl.balance = 0;
                // parent has been made perfectly balanced, as all things should be.
                // as a result, parent's height is unchanged and there is nothing to do.
                return true;
            }

            // parent has a balance of ±2 so we got work to do

            // check if node matches parent's unbalance.
            // balance_plus_one is here guaranteed != 1 as item
            // has increased in height due to the insertion (the
            // first call to this function passes the parent of
            // the new item as item.)
            if (sign * item.parent_balance.avl.balance > 0) {
                // same direction.
                //
                // @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                // The comment, diagram, and equations below assume sign < 0.
                // The other case is symmetric!
                // @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                //
                // Do a clockwise rotation rooted at @parent (A below):
                //
                //           A              B
                //          / \           /   \
                //         B   C?  =>    D     A
                //        / \           / \   / \
                //       D   E?        F?  G?E?  C?
                //      / \
                //     F?  G?
                //
                // Before the rotation:
                //  balance(A) = -2
                //  balance(B) = -1
                // Let x = height(C).  Then:
                //  height(B) = x + 2
                //  height(D) = x + 1
                //  height(E) = x
                //  max(height(F), height(G)) = x.
                //
                // After the rotation:
                //  height(D) = max(height(F), height(G)) + 1
                //      = x + 1
                //  height(A) = max(height(E), height(C)) + 1
                //      = max(x, x) + 1 = x + 1
                //  balance(B) = 0
                //  balance(A) = 0

                rotate(root, parent, -sign);
                parent.parent_balance.avl.balance -= sign;
                item.parent_balance.avl.balance -= sign;
            } else {
                // opposite direction
                // @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                // The comment, diagram, and equations below assume sign < 0.
                // The other case is symmetric!
                // @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                //
                // Do a counterblockwise rotation rooted at @node (B below),
                // then a clockwise rotation rooted at @parent (A below):
                //
                //           A             A           E
                //          / \           / \        /   \
                //         B   C?  =>    E   C? =>  B     A
                //        / \           / \        / \   / \
                //       D?  E         B   G?     D?  F?G?  C?
                //          / \       / \
                //         F?  G?    D?  F?
                //
                // Before the rotation:
                //  balance(A) = -2
                //  balance(B) = +1
                // Let x = height(C).  Then:
                //  height(B) = x + 2
                //  height(E) = x + 1
                //  height(D) = x
                //  max(height(F), height(G)) = x
                //
                // After both rotations:
                //  height(A) = max(height(G), height(C)) + 1
                //     = x + 1
                //  balance(A) = balance(E{orig}) >= 0 ? 0 : -balance(E{orig})
                //  height(B) = max(height(D), height(F)) + 1
                //     = x + 1
                //  balance(B) = balance(E{orig} <= 0) ? 0 : -balance(E{orig})
                //
                //  height(E) = x + 2
                //  balance(E) = 0

                _ = double_rotate(root, item, parent, -sign);
            }
            // rotate doesnt change height, return.
            return true;
        }

        inline fn child_ptr(node: anytype, comptime sign: comptime_int) CopyPtrAttrs(@TypeOf(node), .One, ?*TreeNode) {
            if (sign < 0) {
                return &node.left;
            } else {
                return &node.right;
            }
        }

        inline fn replace_child_or_root(root: *?*TreeNode, parent: ?*TreeNode, old: ?*TreeNode, new: ?*TreeNode) void {
            if (parent) |p| {
                if (old == p.left) {
                    p.left = new;
                } else {
                    p.right = new;
                }
            } else {
                root.* = new;
            }
        }

        fn rotate(root: *?*TreeNode, a: *TreeNode, comptime sign: comptime_int) void {
            const b = child_ptr(a, -sign).*.?;
            const e = child_ptr(b, sign).*;
            const p = a.get_parent();

            child_ptr(a, -sign).* = e;
            a.set_parent(b);

            child_ptr(b, sign).* = a;
            b.set_parent(p);

            if (e) |e_| {
                e_.set_parent(a);
            }

            replace_child_or_root(root, p, a, b);
        }

        inline fn set_parent_and_balance(n: *TreeNode, p: ?*TreeNode, b: i2) void {
            n.parent_balance = .{ .int = (@intFromPtr(p) & ~@as(usize, 3)) | @as(u2, @bitCast(b)) };
        }

        fn double_rotate(root: *?*TreeNode, b: *TreeNode, a: *TreeNode, comptime sign: comptime_int) *TreeNode {
            const e = child_ptr(b, sign).*.?;
            const f = child_ptr(e, -sign).*;
            const g = child_ptr(e, sign).*;
            const p = a.get_parent();

            const eb: i2 = e.parent_balance.avl.balance;

            child_ptr(a, -sign).* = g;
            set_parent_and_balance(a, e, if (sign * eb >= 0) 0 else -eb);

            child_ptr(b, sign).* = f;
            set_parent_and_balance(b, e, if (sign * eb <= 0) 0 else -eb);

            child_ptr(e, sign).* = a;
            child_ptr(e, -sign).* = b;
            set_parent_and_balance(e, p, 0);

            if (g) |g_| {
                g_.set_parent(a);
            }

            if (f) |f_| {
                f_.set_parent(b);
            }

            replace_child_or_root(root, p, a, e);
            return e;
        }

        pub fn fetch_insert(root: *?*TreeNode, item: *T) ?*T {
            if (@sizeOf(Context) != 0)
                @compileError("Cannot infer context " ++ @typeName(Context) ++ ", call fetch_insert_context instead.");
            return fetch_insert_context(root, item, undefined);
        }

        pub fn fetch_insert_context(root: *?*TreeNode, item: *T, ctx: Context) ?*T {
            var cur_ptr = root;
            var parent: ?*TreeNode = null;
            while (cur_ptr.*) |cur| {
                parent = cur;
                switch (Context.cmp(ctx, item, ref_from_node(cur))) {
                    .lt => cur_ptr = &cur.left,
                    .gt => cur_ptr = &cur.right,
                    .eq => {
                        const n = node_from_ref(item);
                        cur_ptr.* = n;
                        set_parent_and_balance(n, parent, cur.parent_balance.avl.balance);
                        return ref_from_node(cur);
                    },
                }
            }
            const n = node_from_ref(item);
            cur_ptr.* = n;
            set_parent_and_balance(n, parent, 0);
            rebalance_after_insert(root, n);
            return null;
        }

        /// insert a node at a parent node
        pub fn insert_at(root: *?*TreeNode, parent: ?*T, sign: comptime_int, item: *T) void {
            const n = node_from_ref(item);
            const parent_node = node_from_optional_ref(parent);
            if (parent_node) |p| {
                child_ptr(p, sign).* = n;
            } else {
                root.* = n;
            }
            set_parent_and_balance(n, parent_node, 0);
            rebalance_after_insert(root, n);
        }

        fn swap_with_successor(root: *?*TreeNode, x: *TreeNode) struct { *TreeNode, bool } {
            var y = x.right.?;

            defer {
                y.left = x.left;
                y.left.?.set_parent(y);

                y.parent_balance = x.parent_balance;
                replace_child_or_root(root, x.get_parent(), x, y);
            }

            if (y.left == null) {
                return .{ y, false };
            } else {
                var q: *TreeNode = undefined;
                while (y.left) |l| {
                    q = y;
                    y = l;
                }

                q.left = y.right;
                if (q.left) |l| {
                    l.set_parent(q);
                }
                y.right = x.right;
                y.right.?.set_parent(y);
                return .{ q, true };
            }
        }

        fn handle_subtree_shrink(root: *?*TreeNode, parent: *TreeNode, comptime sign: comptime_int) struct { ?*TreeNode, bool } {
            const old_balance_factor: i32 = parent.parent_balance.avl.balance;
            if (old_balance_factor == 0) {
                parent.parent_balance.avl.balance += sign;
                // parent is sufficiently balanced but height increased; continue up
                return .{ null, false };
            }
            const new_balance_factor = old_balance_factor + sign;
            const node = if (new_balance_factor == 1) b: {
                parent.parent_balance.avl.balance = 0;
                break :b parent;
            } else b: {
                const node = child_ptr(parent, sign).*.?;
                if (sign * node.parent_balance.avl.balance > 0) {
                    rotate(root, parent, -sign);
                    if (node.parent_balance.avl.balance == 0) {
                        node.parent_balance.avl.balance -= sign;
                        return .{ null, false };
                    } else {
                        parent.parent_balance.avl.balance -= sign;
                        node.parent_balance.avl.balance -= sign;
                    }
                } else {
                    break :b double_rotate(root, node, parent, -sign);
                }
                break :b node;
            };
            const p = node.get_parent();
            return .{ p, if (p) |p_| node == p_.left else false };
        }

        pub fn remove(root: *?*TreeNode, item: *T) void {
            const n: *TreeNode = node_from_ref(item);
            var parent: ?*TreeNode, var left_deleted = if (n.left != null and n.right != null) swap_with_successor(root, n) else b: {
                const c = n.left orelse n.right;
                if (n.get_parent()) |p| {
                    defer if (c) |c1| {
                        c1.set_parent(p);
                    };
                    if (n == p.left) {
                        p.left = c;
                        break :b .{ p, true };
                    } else {
                        p.right = c;
                        break :b .{ p, false };
                    }
                } else {
                    if (c) |c1| {
                        c1.set_parent(null);
                    }
                    root.* = c;
                    return;
                }
            };
            while (parent) |p| {
                parent, left_deleted = if (left_deleted) handle_subtree_shrink(root, p, 1) else handle_subtree_shrink(root, p, -1);
            }
        }

        fn move_in_order(n: *const TreeNode, sign: comptime_int) ?*const TreeNode {
            if (child_ptr(n, sign).*) |c| {
                var n2: *TreeNode = c;
                while (true) {
                    n2 = child_ptr(n2, -sign).* orelse return n2;
                }
            } else {
                var n1: *const TreeNode = n;
                var n2: ?*TreeNode = n.get_parent();
                while (n2 != null and n1 == child_ptr(n2.?, sign).*) {
                    n1 = n2.?;
                    n2 = n1.get_parent();
                }
                return n2;
            }
        }

        pub fn move(n: *const T, sign: comptime_int) ?*const T {
            return ref_from_optional_node(move_in_order(node_from_ref(n), sign));
        }

        pub fn next(n: *const T) ?*T {
            return ref_from_optional_node(move_in_order(node_from_ref(n), 1));
        }

        pub fn prev(n: *const T) ?*T {
            return ref_from_optional_node(move_in_order(node_from_ref(n), -1));
        }

        pub fn extreme_in_order(root: *const ?*TreeNode, sign: comptime_int) ?*T {
            var n: ?*TreeNode = root.*;
            var n2: ?*TreeNode = n;
            while (n) |node| {
                n2 = node;
                n = child_ptr(node, sign).*;
            }
            return ref_from_optional_node(n2);
        }

        pub fn first(root: *const ?*TreeNode) ?*T {
            return extreme_in_order(root, -1);
        }

        pub fn last(root: *const ?*TreeNode) ?*T {
            return extreme_in_order(root, 1);
        }

        pub fn child(item: *const T, sign: comptime_int) ?*T {
            return ref_from_optional_node(child_ptr(node_from_ref(item), sign).*);
        }

        pub fn left(item: *const T) ?*T {
            return ref_from_optional_node(node_from_ref(item).left);
        }

        pub fn right(item: *const T) ?*T {
            return ref_from_optional_node(node_from_ref(item).right);
        }
    };
}

const TestAvlTreeNode = struct {
    // height: u32 = 0,
    value: i32,
    hook: TreeNode = .{},

    // inline fn get_height(self: ?*const TestAvlTreeNode) u32 {
    //     return if (self) |n| n.height else 0;
    // }
};

const TestAvlTree = AvlTree(TestAvlTreeNode, "hook", struct {
    pub fn cmp(_: @This(), lhs: *const TestAvlTreeNode, rhs: *const TestAvlTreeNode) Order {
        return std.math.order(lhs.value, rhs.value);
    }
});

// fn setheights(n: *TestAvlTreeNode) void {
//     if (TestAvlTree.left(n)) |l| _setheights(l);
//     if (TestAvlTree.right(n)) |r| _setheights(r);
//     n.height = TestAvlTreeNode.get_height(TestAvlTree.left(n)) + TestAvlTreeNode.get_height(TestAvlTree.right(n)) + 1;
// }

const testing = std.testing;

test "basic insert/remove" {
    var root: ?*TreeNode = null;
    var a: TestAvlTreeNode = .{ .value = 0 };
    var b: TestAvlTreeNode = .{ .value = 1 };
    var c: TestAvlTreeNode = .{ .value = 2 };
    try testing.expectEqual(null, TestAvlTree.fetch_insert(&root, &a));
    try testing.expectEqual(&a.hook, root);
    try testing.expectEqual(null, TestAvlTree.left(&a));
    try testing.expectEqual(null, TestAvlTree.right(&a));

    try testing.expectEqual(null, TestAvlTree.fetch_insert(&root, &b));
    try testing.expectEqual(&a.hook, root);
    try testing.expectEqual(null, TestAvlTree.left(&a));
    try testing.expectEqual(&b, TestAvlTree.right(&a));

    try testing.expectEqual(null, TestAvlTree.fetch_insert(&root, &c));
    try testing.expectEqual(&b.hook, root);
    try testing.expectEqual(&a, TestAvlTree.left(&b));
    try testing.expectEqual(&c, TestAvlTree.right(&b));

    TestAvlTree.remove(&root, &b);
    try testing.expectEqual(&c.hook, root);
    try testing.expectEqual(&a, TestAvlTree.left(&c));
    try testing.expectEqual(null, TestAvlTree.right(&c));
}

test "iteration" {
    var root: ?*TreeNode = null;
    var a: TestAvlTreeNode = .{ .value = 0 };
    var b: TestAvlTreeNode = .{ .value = 1 };
    var c: TestAvlTreeNode = .{ .value = 2 };
    var d: TestAvlTreeNode = .{ .value = 3 };
    var e: TestAvlTreeNode = .{ .value = 4 };

    {
        var slc: [5]*TestAvlTreeNode = .{ &a, &b, &c, &d, &e };
        var rand = std.Random.DefaultPrng.init(std.testing.random_seed);
        const r = rand.random();
        std.Random.shuffle(r, *TestAvlTreeNode, &slc);
        for (&slc) |item| {
            _ = TestAvlTree.fetch_insert(&root, item);
        }
    }

    var iter = TestAvlTree.first(&root);
    try testing.expectEqual(&a, iter);
    iter = TestAvlTree.next(iter.?);
    try testing.expectEqual(&b, iter);
    iter = TestAvlTree.next(iter.?);
    try testing.expectEqual(&c, iter);
    iter = TestAvlTree.next(iter.?);
    try testing.expectEqual(&d, iter);
    iter = TestAvlTree.next(iter.?);
    try testing.expectEqual(&e, iter);
    iter = TestAvlTree.next(iter.?);
    try testing.expectEqual(null, iter);
}
