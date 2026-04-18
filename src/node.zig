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
    call,
    list,
    range,
    block,
    function,
    binding,
    sequence,
};

pub const PatternTag = enum {
    wildcard,
    identifier,
    literal,
    list,
    group,
};

pub const FunctionBodyTag = enum {
    expression,
    branches,
};

pub const Node = union(Tag) {
    program: Program,
    identifier: Token,
    literal: Token,
    unary: Unary,
    binary: Binary,
    call: Call,
    list: List,
    range: Range,
    block: Block,
    function: Function,
    binding: Binding,
    sequence: Sequence,

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

    pub const Call = struct {
        callee: *Node,
        arguments: []*Node,
    };

    pub const List = struct {
        items: []*Node,
        spread: ?*Node,
    };

    pub const Range = struct {
        start: *Node,
        end: *Node,
    };

    pub const Block = struct {
        expression: *Node,
    };

    pub const Function = struct {
        parameters: []Token,
        body: FunctionBody,
    };

    pub const Binding = struct {
        pattern: *Pattern,
        value: *Node,
        body: *Node,
    };

    pub const Sequence = struct {
        first: *Node,
        second: *Node,
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
            .call => |call| {
                call.callee.deinit(ator);
                for (call.arguments) |argument| argument.deinit(ator);
                ator.free(call.arguments);
            },
            .list => |list| {
                for (list.items) |item| item.deinit(ator);
                ator.free(list.items);
                if (list.spread) |spread| spread.deinit(ator);
            },
            .range => |range| {
                range.start.deinit(ator);
                range.end.deinit(ator);
            },
            .block => |block| block.expression.deinit(ator),
            .function => |*function| {
                ator.free(function.parameters);
                function.body.deinit(ator);
            },
            .binding => |binding| {
                binding.pattern.deinit(ator);
                binding.value.deinit(ator);
                binding.body.deinit(ator);
            },
            .sequence => |sequence| {
                sequence.first.deinit(ator);
                sequence.second.deinit(ator);
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
            .call => |call| {
                try writeTreeKind(term, "call");
                try call.callee.writeTreeIndented(term, indent + 4, "callee");
                for (call.arguments, 0..) |argument, index| {
                    var label_buffer: [32]u8 = undefined;
                    const item_label = try std.fmt.bufPrint(&label_buffer, "arg[{d}]", .{index});
                    try argument.writeTreeIndented(term, indent + 4, item_label);
                }
            },
            .list => |list| {
                try writeTreeKind(term, "list");
                for (list.items, 0..) |item, index| {
                    var label_buffer: [32]u8 = undefined;
                    const item_label = try std.fmt.bufPrint(&label_buffer, "item[{d}]", .{index});
                    try item.writeTreeIndented(term, indent + 4, item_label);
                }
                if (list.spread) |spread| try spread.writeTreeIndented(term, indent + 4, "spread");
            },
            .range => |range| {
                try writeTreeKind(term, "range");
                try range.start.writeTreeIndented(term, indent + 4, "start");
                try range.end.writeTreeIndented(term, indent + 4, "end");
            },
            .block => |block| {
                try writeTreeKind(term, "block");
                try block.expression.writeTreeIndented(term, indent + 4, "expression");
            },
            .function => |function| {
                try writeTreeKind(term, "function");
                try writeIndent(writer, indent + 4);
                try writeTreeWord(term, "parameters", .cyan);
                if (function.parameters.len == 0) {
                    try writer.writeByte('\n');
                } else {
                    try term.setColor(.dim);
                    try writer.writeByte(':');
                    try term.setColor(.reset);
                    for (function.parameters) |parameter| {
                        try writer.writeByte(' ');
                        try term.setColor(parameter.color());
                        try writer.writeAll(parameter.lexeme);
                        try term.setColor(.reset);
                    }
                    try writer.writeByte('\n');
                }
                switch (function.body) {
                    .expression => |body_expression| try body_expression.writeTreeIndented(term, indent + 4, "body"),
                    .branches => |branches| {
                        try writeIndent(writer, indent + 4);
                        try writeTreeWord(term, "branches", .magenta);
                        try writer.writeByte('\n');
                        for (branches, 0..) |branch, index| {
                            var label_buffer: [32]u8 = undefined;
                            const branch_label = try std.fmt.bufPrint(&label_buffer, "branch[{d}]", .{index});
                            try writeBranchTree(branch, term, indent + 8, branch_label);
                        }
                    },
                }
            },
            .binding => |binding| {
                try writeTreeKind(term, "binding");
                try writePatternTree(binding.pattern, term, indent + 4, "pattern");
                try binding.value.writeTreeIndented(term, indent + 4, "value");
                try binding.body.writeTreeIndented(term, indent + 4, "body");
            },
            .sequence => |sequence| {
                try writeTreeKind(term, "sequence");
                try sequence.first.writeTreeIndented(term, indent + 4, "first");
                try sequence.second.writeTreeIndented(term, indent + 4, "second");
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

pub const FunctionBody = union(FunctionBodyTag) {
    expression: *Node,
    branches: []*Branch,

    pub fn deinit(self: *FunctionBody, ator: Allocator) void {
        switch (self.*) {
            .expression => |expression| expression.deinit(ator),
            .branches => |branches| {
                for (branches) |branch| branch.deinit(ator);
                ator.free(branches);
            },
        }
    }
};

pub const Branch = struct {
    patterns: ?[]*Pattern,
    guard: ?*Node,
    result: *Node,

    pub fn create(
        ator: Allocator,
        patterns: ?[]*Pattern,
        guard: ?*Node,
        result: *Node,
    ) !*Branch {
        const ptr = try ator.create(Branch);
        ptr.* = .{
            .patterns = patterns,
            .guard = guard,
            .result = result,
        };
        return ptr;
    }

    pub fn deinit(self: *Branch, ator: Allocator) void {
        if (self.patterns) |patterns| {
            for (patterns) |pattern| pattern.deinit(ator);
            ator.free(patterns);
        }
        if (self.guard) |guard| guard.deinit(ator);
        self.result.deinit(ator);
        ator.destroy(self);
    }
};

pub const Pattern = union(PatternTag) {
    wildcard: void,
    identifier: Token,
    literal: Token,
    list: ListPattern,
    group: *Pattern,

    pub const ListPattern = struct {
        items: []*Pattern,
        spread: ?*Pattern,
    };

    pub fn create(ator: Allocator, pattern: Pattern) !*Pattern {
        const ptr = try ator.create(Pattern);
        ptr.* = pattern;
        return ptr;
    }

    pub fn deinit(self: *Pattern, ator: Allocator) void {
        switch (self.*) {
            .wildcard, .identifier, .literal => {},
            .group => |inner| inner.deinit(ator),
            .list => |list| {
                for (list.items) |item| item.deinit(ator);
                ator.free(list.items);
                if (list.spread) |spread| spread.deinit(ator);
            },
        }
        ator.destroy(self);
    }
};

fn writeBranchTree(branch: *const Branch, term: Terminal, indent: usize, label: []const u8) !void {
    const writer = term.writer;
    try writeIndent(writer, indent);
    try Node.writeTreeLabel(term, label);
    try Node.writeTreeWord(term, "branch", .magenta);
    try writer.writeByte('\n');

    if (branch.patterns) |patterns| {
        for (patterns, 0..) |pattern, index| {
            var label_buffer: [32]u8 = undefined;
            const item_label = try std.fmt.bufPrint(&label_buffer, "pattern[{d}]", .{index});
            try writePatternTree(pattern, term, indent + 4, item_label);
        }
    } else {
        try writeIndent(writer, indent + 4);
        try Node.writeTreeLabel(term, "patterns");
        try Node.writeTreeWord(term, "implicit-parameters", .dim);
        try writer.writeByte('\n');
    }

    if (branch.guard) |guard| {
        try guard.writeTreeIndented(term, indent + 4, "guard");
    } else {
        try writeIndent(writer, indent + 4);
        try Node.writeTreeLabel(term, "guard");
        try Node.writeTreeWord(term, "none", .dim);
        try writer.writeByte('\n');
    }

    try branch.result.writeTreeIndented(term, indent + 4, "result");
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
        .literal => |token| try Node.writeTreeTokenLine(term, "literal", token),
        .group => |inner| {
            try Node.writeTreeKind(term, "group");
            try writePatternTree(inner, term, indent + 4, "inner");
        },
        .list => |list| {
            try Node.writeTreeKind(term, "list");
            for (list.items, 0..) |item, index| {
                var label_buffer: [32]u8 = undefined;
                const item_label = try std.fmt.bufPrint(&label_buffer, "item[{d}]", .{index});
                try writePatternTree(item, term, indent + 4, item_label);
            }
            if (list.spread) |spread| try writePatternTree(spread, term, indent + 4, "spread");
        },
    }
}


fn writeIndent(writer: anytype, indent: usize) !void {
    var remaining = indent;
    while (remaining != 0) : (remaining -= 1) try writer.writeByte(' ');
}
