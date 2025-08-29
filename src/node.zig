const std = @import("std");
const Allocator = std.mem.Allocator;
const FormatOptions = std.fmt.FormatOptions;
const print = std.debug.print;
const testing = std.testing;

const ansi = @import("ansi.zig");
const Lexer = @import("Lexer.zig");
const Token = @import("Token.zig");

const String = std.ArrayList(u8);

pub const Tag = enum {
    program,
    primary,
    binary,
    function,
    apply,
    let_in,
    let_rec_in,
    if_then_else,

    pub fn format(
        self: Tag,
        writer: anytype,
    ) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Node = union(Tag) {
    program: Program,
    primary: Primary,
    binary: Binary,
    function: Function,
    apply: Apply,
    let_in: LetIn,
    let_rec_in: LetRecIn,
    if_then_else: IfThenElse,

    pub fn tag(self: Node) Tag {
        return @as(Tag, self);
    }

    pub const Program = struct {
        expression: ?*Node,

        pub fn init(ator: Allocator, expression: ?*Node) !*Node {
            const node = try ator.create(Node);
            node.* = Node{ .program = .{ .expression = expression } };
            return node;
        }

        fn deinit(self: *Program, ator: Allocator) void {
            if (self.expression) |expression| {
                expression.deinit(ator);
            }
            ator.destroy(@as(*Node, @fieldParentPtr("program", self)));
        }

        fn clone(self: *Program, ator: Allocator) !*Node {
            const expression = if (self.expression) |expression|
                try expression.clone(ator)
            else
                null;

            return try Program.init(ator, expression);
        }
    };

    pub const Primary = struct {
        operand: Token,

        pub fn init(ator: Allocator, operand: Token) !*Node {
            const node = try ator.create(Node);
            node.* = Node{
                .primary = .{ .operand = operand },
            };
            return node;
        }

        fn deinit(self: *Primary, ator: Allocator) void {
            ator.destroy(@as(*Node, @fieldParentPtr("primary", self)));
        }

        fn clone(self: *Primary, ator: Allocator) !*Node {
            return try Primary.init(ator, self.operand);
        }
    };

    pub const LetIn = struct {
        name: Token,
        value: *Node,
        body: *Node,

        pub fn init(ator: Allocator, name: Token, value: *Node, body: *Node) !*Node {
            const node = try ator.create(Node);
            node.* = Node{ .let_in = .{ .name = name, .value = value, .body = body } };
            return node;
        }

        pub fn deinit(self: *LetIn, ator: Allocator) void {
            self.value.deinit(ator);
            self.body.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("let_in", self)));
        }

        pub fn clone(self: *LetIn, ator: Allocator) !*Node {
            const value = try self.value.clone(ator);
            const body = try self.body.clone(ator);
            return try LetIn.init(ator, self.name, value, body);
        }
    };

    pub const LetRecIn = struct {
        name: Token,
        value: *Node,
        body: *Node,

        pub fn init(ator: Allocator, name: Token, value: *Node, body: *Node) !*Node {
            const node = try ator.create(Node);
            node.* = Node{ .let_rec_in = .{ .name = name, .value = value, .body = body } };
            return node;
        }

        pub fn deinit(self: *LetRecIn, ator: Allocator) void {
            self.value.deinit(ator);
            self.body.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("let_rec_in", self)));
        }

        pub fn clone(self: *LetRecIn, ator: Allocator) !*Node {
            const value = try self.value.clone(ator);
            const body = try self.body.clone(ator);
            return try LetRecIn.init(ator, self.name, value, body);
        }
    };

    pub const IfThenElse = struct {
        condition: *Node,
        consequent: *Node,
        alternate: *Node,

        pub fn init(
            ator: Allocator,
            condition: *Node,
            consequent: *Node,
            alternate: *Node,
        ) !*Node {
            const node = try ator.create(Node);
            node.* = Node{ .if_then_else = .{
                .condition = condition,
                .consequent = consequent,
                .alternate = alternate,
            } };
            return node;
        }

        pub fn deinit(self: *IfThenElse, ator: Allocator) void {
            self.condition.deinit(ator);
            self.consequent.deinit(ator);
            self.alternate.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("if_then_else", self)));
        }

        pub fn clone(self: *IfThenElse, ator: Allocator) !*Node {
            const condition = try self.condition.clone(ator);
            const consequent = try self.consequent.clone(ator);
            const alternate = try self.alternate.clone(ator);
            return try IfThenElse.init(ator, condition, consequent, alternate);
        }
    };

    pub const Function = struct {
        parameter: Token,
        body: *Node,

        pub fn init(ator: Allocator, parameter: Token, body: *Node) !*Node {
            const node = try ator.create(Node);
            node.* = Node{
                .function = .{ .parameter = parameter, .body = body },
            };
            return node;
        }

        fn deinit(self: *Function, ator: Allocator) void {
            self.body.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("function", self)));
        }

        pub fn clone(self: *Function, ator: Allocator) !*Node {
            const body = try self.body.clone(ator);
            return try Function.init(ator, self.parameter, body);
        }
    };

    pub const Apply = struct {
        function: *Node,
        argument: *Node,

        pub fn init(
            ator: Allocator,
            function: *Node,
            argument: *Node,
        ) !*Node {
            const node = try ator.create(Node);
            node.* = Node{
                .apply = .{
                    .function = function,
                    .argument = argument,
                },
            };
            return node;
        }

        pub fn deinit(self: *Apply, ator: Allocator) void {
            self.function.deinit(ator);
            self.argument.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("apply", self)));
        }

        pub fn clone(self: *Apply, ator: Allocator) !*Node {
            const function = try self.function.clone(ator);
            const argument = try self.argument.clone(ator);
            return try Apply.init(ator, function, argument);
        }
    };

    pub const Binary = struct {
        left: *Node,
        operator: Token,
        right: *Node,

        pub fn init(ator: Allocator, left: *Node, operator: Token, right: *Node) !*Node {
            const node = try ator.create(Node);
            node.* = Node{ .binary = .{
                .left = left,
                .operator = operator,
                .right = right,
            } };
            return node;
        }

        pub fn deinit(self: *Binary, ator: Allocator) void {
            self.left.deinit(ator);
            self.right.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("binary", self)));
        }

        pub fn clone(self: *Binary, ator: Allocator) !*Node {
            const left = try self.left.clone(ator);
            const right = try self.right.clone(ator);
            return try Binary.init(ator, left, self.operator, right);
        }
    };

    pub fn deinit(self: *Node, ator: Allocator) void {
        switch (self.*) {
            .program => |*program| program.deinit(ator),
            .primary => |*primary| primary.deinit(ator),
            .binary => |*binary| binary.deinit(ator),
            .function => |*function| function.deinit(ator),
            .apply => |*apply| apply.deinit(ator),
            .let_in => |*let_in| let_in.deinit(ator),
            .let_rec_in => |*let_rec_in| let_rec_in.deinit(ator),
            .if_then_else => |*if_then_else| if_then_else.deinit(ator),
        }
    }

    pub fn clone(self: *Node, ator: Allocator) anyerror!*Node {
        return switch (self.*) {
            .program => |*program| try program.clone(ator),
            .primary => |*primary| try primary.clone(ator),
            .binary => |*binary| try binary.clone(ator),
            .function => |*function| try function.clone(ator),
            .apply => |*apply| try apply.clone(ator),
            .let_in => |*let_in| try let_in.clone(ator),
            .let_rec_in => |*let_rec_in| try let_rec_in.clone(ator),
            .if_then_else => |*if_then_else| try if_then_else.clone(ator),
        };
    }

    pub fn format(
        self: *Node,
        writer: anytype,
    ) !void {
        switch (self.*) {
            .program => |program| if (program.expression) |expression|
                try expression.format(writer),
            .primary => |primary| {
                const operand = primary.operand;
                try writer.print("{s}", .{operand.lexeme});
            },
            .binary => |binary| {
                //try writer.print("(", .{});
                try binary.left.format(writer);
                try writer.print(" {s} ", .{binary.operator.lexeme});
                try binary.right.format(writer);
                //try writer.print(")", .{});
            },
            .function => |function| {
                try writer.print("(λ{s}. ", .{function.parameter.lexeme});
                try function.body.format(writer);
                try writer.print(")", .{});
            },
            .apply => |apply| {
                try apply.function.format(writer);
                try writer.print(" ", .{});
                try apply.argument.format(writer);
            },
            .let_in => |let_in| {
                try writer.print("\nlet ", .{});
                try let_in.name.format(writer);
                try writer.print(" = ", .{});
                try let_in.value.format(writer);
                try writer.print(" in ", .{});
                if (let_in.body.tag() != .let_in) {
                    try writer.print("\n  ", .{});
                }
                try let_in.body.format(writer);
            },
            .let_rec_in => |let_rec_in| {
                try writer.print("\nlet rec ", .{});
                try let_rec_in.name.format(writer);
                try writer.print(" = ", .{});
                try let_rec_in.value.format(writer);
                try writer.print(" in ", .{});
                if (let_rec_in.body.tag() != .let_in) {
                    try writer.print("\n  ", .{});
                }
                try let_rec_in.body.format(writer);
            },
            .if_then_else => |if_then_else| {
                try writer.print("if ", .{});
                try if_then_else.condition.format(writer);
                try writer.print(" then ", .{});
                try if_then_else.consequent.format(writer);
                try writer.print(" else ", .{});
                try if_then_else.alternate.format(writer);
            },
        }
    }

    pub fn equal(node_a: *Node, node_b: *Node) bool {
        if (node_a.tag() != node_b.tag()) {
            return false;
        }
        return switch (node_a.*) {
            .program => |a| {
                const b = node_b.program;
                if (a.expression == null or b.expression == null)
                    return a.expression == b.expression;
                return a.expression.?.equal(b.expression.?);
            },
            .primary => |a| {
                const b = node_b.primary;
                return a.operand.equal(b.operand);
            },
            .binary => |a| {
                const b = node_b.binary;
                return a.left.equal(b.left) and
                    a.operator.equal(b.operator) and
                    a.right.equal(b.right);
            },
            .function => |a| {
                const b = node_b.function;
                return a.parameter.equal(b.parameter) and a.body.equal(b.body);
            },
            .apply => |a| {
                const b = node_b.apply;
                return a.function.equal(b.function) and a.argument.equal(b.argument);
            },
            .let_in => |a| {
                const b = node_b.let_in;
                return a.name.equal(b.name) and a.value.equal(b.value) and a.body.equal(b.body);
            },
            .let_rec_in => |a| {
                const b = node_b.let_rec_in;
                return a.name.equal(b.name) and a.value.equal(b.value) and a.body.equal(b.body);
            },
            .if_then_else => |a| {
                const b = node_b.if_then_else;
                return a.condition.equal(b.condition) and
                    a.consequent.equal(b.consequent) and
                    a.alternate.equal(b.alternate);
            },
        };
    }
};
