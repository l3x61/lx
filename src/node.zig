const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Terminal = Io.Terminal;
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
    map,
    function,
    binding,
};

pub const PatternTag = enum {
    wildcard,
    identifier,
    literal,
    tuple,
    list,
    map,
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
    map: Map,
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

    pub const Map = struct {
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
            .map => |map| {
                for (map.entries) |entry| {
                    ator.free(entry.key);
                    entry.value.deinit(ator);
                }
                ator.free(map.entries);
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

    pub fn writeTree(self: *const Node, term: Terminal) anyerror!void {
        try self.writeTreeIndented(term, 0, null);
    }

    fn writeTreeIndented(self: *const Node, term: Terminal, indent: usize, label: ?[]const u8) anyerror!void {
        const writer = term.writer;
        try writeIndent(writer, indent);
        if (label) |value| try writeTreeLabel(term, value);

        switch (self.*) {
            .program => {
                try writeTreeKind(term, "program");
                try self.program.expression.writeTreeIndented(term, indent + 4, null);
            },
            .identifier => |token| try writeTreeTokenLine(term, "identifier", token),
            .literal => |token| try writeTreeTokenLine(term, "literal", token),
            .unary => |unary| {
                try writeTreeKindWithToken(term, "unary", unary.operator);
                try unary.operand.writeTreeIndented(term, indent + 4, "operand");
            },
            .binary => |binary| {
                try writeTreeKindWithToken(term, "binary", binary.operator);
                try binary.left.writeTreeIndented(term, indent + 4, "left");
                try binary.right.writeTreeIndented(term, indent + 4, "right");
            },
            .application => |app| {
                try writeTreeKind(term, "application");
                try app.callee.writeTreeIndented(term, indent + 4, "callee");
                try app.argument.writeTreeIndented(term, indent + 4, "argument");
            },
            .index => |idx| {
                try writeTreeKind(term, "index");
                try idx.target.writeTreeIndented(term, indent + 4, "target");
                try idx.index.writeTreeIndented(term, indent + 4, "index");
            },
            .list => |list| {
                try writeTreeKind(term, "list");
                for (list.items, 0..) |item, index| {
                    var label_buffer: [32]u8 = undefined;
                    const item_label = try std.fmt.bufPrint(&label_buffer, "item[{d}]", .{index});
                    try item.writeTreeIndented(term, indent + 4, item_label);
                }
            },
            .tuple => |tuple| {
                try writeTreeKind(term, "tuple");
                for (tuple.items, 0..) |item, index| {
                    var label_buffer: [32]u8 = undefined;
                    const item_label = try std.fmt.bufPrint(&label_buffer, "item[{d}]", .{index});
                    try item.writeTreeIndented(term, indent + 4, item_label);
                }
            },
            .map => |map| {
                try writeTreeKind(term, "map");
                for (map.entries, 0..) |entry, index| {
                    var key_label_buffer: [32]u8 = undefined;
                    const key_label = try std.fmt.bufPrint(&key_label_buffer, "entry[{d}].key", .{index});
                    try writeIndent(term.writer, indent + 4);
                    try writeTreeLabel(term, key_label);
                    try writeTreeWord(term, "key", .magenta);
                    try term.writer.print(" \"{s}\"\n", .{entry.key});
                    var value_label_buffer: [32]u8 = undefined;
                    const value_label = try std.fmt.bufPrint(&value_label_buffer, "entry[{d}].value", .{index});
                    try entry.value.writeTreeIndented(term, indent + 4, value_label);
                }
            },
            .function => |function| {
                try writeTreeKind(term, "function");
                for (function.clauses, 0..) |clause, index| {
                    var label_buffer: [32]u8 = undefined;
                    const clause_label = try std.fmt.bufPrint(&label_buffer, "clause[{d}]", .{index});
                    try writeClauseTree(clause, term, indent + 4, clause_label);
                }
            },
            .binding => |binding| {
                try writeTreeKind(term, "binding");
                try writePatternTree(binding.pattern, term, indent + 4, "pattern");
                try binding.value.writeTreeIndented(term, indent + 4, "value");
                try binding.body.writeTreeIndented(term, indent + 4, "body");
            },
        }
    }

    fn writeTreeKind(term: Terminal, name: []const u8) !void {
        try writeTreeWord(term, name, .magenta);
        try term.writer.writeByte('\n');
    }

    fn writeTreeTokenLine(term: Terminal, kind: []const u8, token: Token) !void {
        try writeTreeWord(term, kind, .magenta);
        try term.writer.writeByte(' ');
        try term.setColor(token.color());
        try term.writer.writeAll(token.lexeme);
        try term.setColor(.reset);
        try term.writer.writeByte('\n');
    }

    fn writeTreeKindWithToken(term: Terminal, kind: []const u8, token: Token) !void {
        try writeTreeTokenLine(term, kind, token);
    }

    fn writeTreeLabel(term: Terminal, label: []const u8) !void {
        try term.setColor(.dim);
        try term.writer.writeAll(label);
        try term.writer.writeAll(": ");
        try term.setColor(.reset);
    }

    fn writeTreeWord(term: Terminal, value: []const u8, color: Terminal.Color) !void {
        try term.setColor(color);
        try term.writer.writeAll(value);
        try term.setColor(.reset);
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
    map: MapPattern,
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

    pub const MapPattern = struct {
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
            .map => |map| {
                for (map.entries) |entry| {
                    ator.free(entry.key);
                    entry.pattern.deinit(ator);
                }
                ator.free(map.entries);
                switch (map.rest) {
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

fn writeClauseTree(clause: *const Clause, term: Terminal, indent: usize, label: []const u8) !void {
    const writer = term.writer;
    try writeIndent(writer, indent);
    try Node.writeTreeLabel(term, label);
    try Node.writeTreeWord(term, "clause", .magenta);
    try writer.writeByte('\n');

    try writePatternTree(clause.pattern, term, indent + 4, "pattern");
    try clause.body.writeTreeIndented(term, indent + 4, "body");
}

fn writePatternTree(pattern: *const Pattern, term: Terminal, indent: usize, label: []const u8) !void {
    const writer = term.writer;
    try writeIndent(writer, indent);
    try Node.writeTreeLabel(term, label);
    switch (pattern.*) {
        .wildcard => {
            try Node.writeTreeWord(term, "wildcard", .magenta);
            try writer.writeByte('\n');
        },
        .identifier => |token| try Node.writeTreeTokenLine(term, "identifier", token),
        .literal => |lit| {
            try Node.writeTreeWord(term, "literal", .magenta);
            try writer.writeByte(' ');
            if (lit.negate) try writer.writeByte('-');
            try term.setColor(lit.token.color());
            try writer.writeAll(lit.token.lexeme);
            try term.setColor(.reset);
            try writer.writeByte('\n');
        },
        .tuple => |tuple| {
            try Node.writeTreeKind(term, "tuple");
            for (tuple.items, 0..) |item, index| {
                var label_buffer: [32]u8 = undefined;
                const item_label = try std.fmt.bufPrint(&label_buffer, "item[{d}]", .{index});
                try writePatternTree(item, term, indent + 4, item_label);
            }
        },
        .list => |list| {
            try Node.writeTreeKind(term, "list");
            for (list.items, 0..) |item, index| {
                var label_buffer: [32]u8 = undefined;
                const item_label = try std.fmt.bufPrint(&label_buffer, "item[{d}]", .{index});
                try writePatternTree(item, term, indent + 4, item_label);
            }
            switch (list.rest) {
                .none => {},
                .wildcard => {
                    try writeIndent(writer, indent + 4);
                    try Node.writeTreeLabel(term, "rest");
                    try Node.writeTreeWord(term, "any", .magenta);
                    try writer.writeByte('\n');
                },
                .pattern => |p| try writePatternTree(p, term, indent + 4, "rest"),
            }
        },
        .map => |map| {
            try Node.writeTreeKind(term, "map");
            for (map.entries, 0..) |entry, index| {
                var label_buffer: [128]u8 = undefined;
                const entry_label = try std.fmt.bufPrint(&label_buffer, "entry[{d}] \"{s}\"", .{ index, entry.key });
                try writePatternTree(entry.pattern, term, indent + 4, entry_label);
            }
            switch (map.rest) {
                .none => {},
                .wildcard => {
                    try writeIndent(writer, indent + 4);
                    try Node.writeTreeLabel(term, "rest");
                    try Node.writeTreeWord(term, "any", .magenta);
                    try writer.writeByte('\n');
                },
                .pattern => |p| try writePatternTree(p, term, indent + 4, "rest"),
            }
        },
        .refinement => |r| {
            try Node.writeTreeKind(term, "refinement");
            try writePatternTree(r.base, term, indent + 4, "base");
            try r.condition.writeTreeIndented(term, indent + 4, "condition");
        },
        .alternative => |a| {
            try Node.writeTreeKind(term, "alternative");
            try writePatternTree(a.left, term, indent + 4, "left");
            try writePatternTree(a.right, term, indent + 4, "right");
        },
    }
}

fn writeIndent(writer: anytype, indent: usize) !void {
    var remaining = indent;
    while (remaining != 0) : (remaining -= 1) try writer.writeByte(' ');
}
