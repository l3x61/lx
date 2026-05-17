const std = @import("std");
const Allocator = std.mem.Allocator;
const Token = @import("Token.zig");

pub const Tag = enum {
    program,
    identifier,
    literal,
    unary,
    binary,
    application,
    index,
    list,
    tuple,
    record,
    function,
    binding,
};

pub const PatternTag = enum {
    wildcard,
    identifier,
    literal,
    tuple,
    list,
    record,
    refinement,
    alternative,
};

pub const Node = union(Tag) {
    program: Program,
    identifier: Token,
    literal: Token,
    unary: Unary,
    binary: Binary,
    application: Application,
    index: Index,
    list: List,
    tuple: Tuple,
    record: Record,
    function: Function,
    binding: Binding,

    pub const Program = struct {
        expression: *Node,
    };

    pub const Unary = struct {
        operator: Token,
        operand: *Node,
    };

    pub const Binary = struct {
        left: *Node,
        operator: Token,
        right: *Node,
    };

    pub const Application = struct {
        callee: *Node,
        argument: *Node,
    };

    pub const Index = struct {
        target: *Node,
        index: *Node,
    };

    pub const List = struct {
        items: []*Node,
    };

    pub const Tuple = struct {
        items: []*Node,
    };

    pub const Record = struct {
        entries: []Entry,

        pub const Entry = struct {
            key: []const u8,
            value: *Node,
        };
    };

    pub const Function = struct {
        clauses: []*Clause,
    };

    pub const Binding = struct {
        pattern: *Pattern,
        value: *Node,
        body: *Node,
    };

    pub fn create(ator: Allocator, node: Node) !*Node {
        const ptr = try ator.create(Node);
        ptr.* = node;
        return ptr;
    }

    pub fn deinit(self: *Node, ator: Allocator) void {
        switch (self.*) {
            .program => |program| program.expression.deinit(ator),
            .identifier, .literal => {},
            .unary => |unary| unary.operand.deinit(ator),
            .binary => |binary| {
                binary.left.deinit(ator);
                binary.right.deinit(ator);
            },
            .application => |app| {
                app.callee.deinit(ator);
                app.argument.deinit(ator);
            },
            .index => |idx| {
                idx.target.deinit(ator);
                idx.index.deinit(ator);
            },
            .list => |list| {
                for (list.items) |item| item.deinit(ator);
                ator.free(list.items);
            },
            .tuple => |tuple| {
                for (tuple.items) |item| item.deinit(ator);
                ator.free(tuple.items);
            },
            .record => |record| {
                for (record.entries) |entry| {
                    ator.free(entry.key);
                    entry.value.deinit(ator);
                }
                ator.free(record.entries);
            },
            .function => |function| {
                for (function.clauses) |clause| clause.deinit(ator);
                ator.free(function.clauses);
            },
            .binding => |binding| {
                binding.pattern.deinit(ator);
                binding.value.deinit(ator);
                binding.body.deinit(ator);
            },
        }
        ator.destroy(self);
    }

};

pub const Clause = struct {
    pattern: *Pattern,
    body: *Node,

    pub fn create(ator: Allocator, pattern: *Pattern, body: *Node) !*Clause {
        const ptr = try ator.create(Clause);
        ptr.* = .{ .pattern = pattern, .body = body };
        return ptr;
    }

    pub fn deinit(self: *Clause, ator: Allocator) void {
        self.pattern.deinit(ator);
        self.body.deinit(ator);
        ator.destroy(self);
    }
};

pub const Rest = union(enum) {
    none: void,
    wildcard: void,
    pattern: *Pattern,
};

pub const Pattern = union(PatternTag) {
    wildcard: void,
    identifier: Token,
    literal: LiteralPattern,
    tuple: TuplePattern,
    list: ListPattern,
    record: RecordPattern,
    refinement: Refinement,
    alternative: Alternative,

    pub const LiteralPattern = struct {
        token: Token,
        negate: bool,
    };

    pub const TuplePattern = struct {
        items: []*Pattern,
    };

    pub const ListPattern = struct {
        items: []*Pattern,
        rest: Rest,
    };

    pub const RecordPattern = struct {
        entries: []Entry,
        rest: Rest,

        pub const Entry = struct {
            key: []const u8,
            pattern: *Pattern,
        };
    };

    pub const Refinement = struct {
        base: *Pattern,
        condition: *Node,
    };

    pub const Alternative = struct {
        left: *Pattern,
        right: *Pattern,
    };

    pub fn create(ator: Allocator, pattern: Pattern) !*Pattern {
        const ptr = try ator.create(Pattern);
        ptr.* = pattern;
        return ptr;
    }

    pub fn deinit(self: *Pattern, ator: Allocator) void {
        switch (self.*) {
            .wildcard, .identifier, .literal => {},
            .tuple => |tuple| {
                for (tuple.items) |item| item.deinit(ator);
                ator.free(tuple.items);
            },
            .list => |list| {
                for (list.items) |item| item.deinit(ator);
                ator.free(list.items);
                switch (list.rest) {
                    .pattern => |p| p.deinit(ator),
                    else => {},
                }
            },
            .record => |record| {
                for (record.entries) |entry| {
                    ator.free(entry.key);
                    entry.pattern.deinit(ator);
                }
                ator.free(record.entries);
                switch (record.rest) {
                    .pattern => |p| p.deinit(ator),
                    else => {},
                }
            },
            .refinement => |r| {
                r.base.deinit(ator);
                r.condition.deinit(ator);
            },
            .alternative => |a| {
                a.left.deinit(ator);
                a.right.deinit(ator);
            },
        }
        ator.destroy(self);
    }
};

