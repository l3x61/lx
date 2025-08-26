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
    abstraction,
    application,
    let_in,
    let_rec_in,
    if_then_else,

    pub fn format(
        self: Tag,
        comptime _: []const u8,
        _: FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Node = union(Tag) {
    program: Program,
    primary: Primary,
    abstraction: Abstraction,
    application: Application,
    let_in: LetIn,
    let_rec_in: LetRecIn,
    if_then_else: IfThenElse,

    pub fn tag(self: Node) Tag {
        return @as(Tag, self);
    }

    pub const Program = struct {
        expression: ?*Node,

        pub fn init(allocator: Allocator, expression: ?*Node) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{ .program = .{ .expression = expression } };
            return node;
        }

        fn deinit(self: *Program, allocator: Allocator) void {
            if (self.expression) |expression| {
                expression.deinit(allocator);
            }
            allocator.destroy(@as(*Node, @fieldParentPtr("program", self)));
        }

        fn clone(self: *Program, allocator: Allocator) !*Node {
            const expression = if (self.expression) |expression|
                try expression.clone(allocator)
            else
                null;

            return try Program.init(allocator, expression);
        }
    };

    pub const Primary = struct {
        operand: Token,

        pub fn init(allocator: Allocator, operand: Token) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .primary = .{ .operand = operand },
            };
            return node;
        }

        fn deinit(self: *Primary, allocator: Allocator) void {
            allocator.destroy(@as(*Node, @fieldParentPtr("primary", self)));
        }

        fn clone(self: *Primary, allocator: Allocator) !*Node {
            return try Primary.init(allocator, self.operand);
        }
    };

    pub const LetIn = struct {
        name: Token,
        value: *Node,
        body: *Node,

        pub fn init(allocator: Allocator, name: Token, value: *Node, body: *Node) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{ .let_in = .{ .name = name, .value = value, .body = body } };
            return node;
        }

        pub fn deinit(self: *LetIn, allocator: Allocator) void {
            self.value.deinit(allocator);
            self.body.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("let_in", self)));
        }

        pub fn clone(self: *LetIn, allocator: Allocator) !*Node {
            const value = try self.value.clone(allocator);
            const body = try self.body.clone(allocator);
            return try LetIn.init(allocator, self.name, value, body);
        }
    };

    pub const LetRecIn = struct {
        name: Token,
        value: *Node,
        body: *Node,

        pub fn init(allocator: Allocator, name: Token, value: *Node, body: *Node) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{ .let_rec_in = .{ .name = name, .value = value, .body = body } };
            return node;
        }

        pub fn deinit(self: *LetRecIn, allocator: Allocator) void {
            self.value.deinit(allocator);
            self.body.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("let_rec_in", self)));
        }

        pub fn clone(self: *LetRecIn, allocator: Allocator) !*Node {
            const value = try self.value.clone(allocator);
            const body = try self.body.clone(allocator);
            return try LetRecIn.init(allocator, self.name, value, body);
        }
    };

    pub const IfThenElse = struct {
        condition: *Node,
        consequent: *Node,
        alternate: *Node,

        pub fn init(
            allocator: Allocator,
            condition: *Node,
            consequent: *Node,
            alternate: *Node,
        ) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{ .if_then_else = .{
                .condition = condition,
                .consequent = consequent,
                .alternate = alternate,
            } };
            return node;
        }

        pub fn deinit(self: *IfThenElse, allocator: Allocator) void {
            self.condition.deinit(allocator);
            self.consequent.deinit(allocator);
            self.alternate.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("if_then_else", self)));
        }

        pub fn clone(self: *IfThenElse, allocator: Allocator) !*Node {
            const condition = try self.condition.clone(allocator);
            const consequent = try self.consequent.clone(allocator);
            const alternate = try self.alternate.clone(allocator);
            return try IfThenElse.init(allocator, condition, consequent, alternate);
        }
    };

    pub const Abstraction = struct {
        parameter: Token,
        body: *Node,

        pub fn init(allocator: Allocator, parameter: Token, body: *Node) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .abstraction = .{ .parameter = parameter, .body = body },
            };
            return node;
        }

        fn deinit(self: *Abstraction, allocator: Allocator) void {
            self.body.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("abstraction", self)));
        }

        pub fn clone(self: *Abstraction, allocator: Allocator) !*Node {
            const body = try self.body.clone(allocator);
            return try Abstraction.init(allocator, self.parameter, body);
        }
    };

    pub const Application = struct {
        abstraction: *Node,
        argument: *Node,

        pub fn init(
            allocator: Allocator,
            abstraction: *Node,
            argument: *Node,
        ) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .application = .{
                    .abstraction = abstraction,
                    .argument = argument,
                },
            };
            return node;
        }

        pub fn deinit(self: *Application, allocator: Allocator) void {
            self.abstraction.deinit(allocator);
            self.argument.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("application", self)));
        }

        pub fn clone(self: *Application, allocator: Allocator) !*Node {
            const abstraction = try self.abstraction.clone(allocator);
            const argument = try self.argument.clone(allocator);
            return try Application.init(allocator, abstraction, argument);
        }
    };

    pub fn deinit(self: *Node, allocator: Allocator) void {
        switch (self.*) {
            .program => |*program| program.deinit(allocator),
            .primary => |*primary| primary.deinit(allocator),
            .abstraction => |*abstraction| abstraction.deinit(allocator),
            .application => |*application| application.deinit(allocator),
            .let_in => |*let_in| let_in.deinit(allocator),
            .let_rec_in => |*let_rec_in| let_rec_in.deinit(allocator),
            .if_then_else => |*if_then_else| if_then_else.deinit(allocator),
        }
    }

    pub fn clone(self: *Node, allocator: Allocator) anyerror!*Node {
        return switch (self.*) {
            .program => |*program| try program.clone(allocator),
            .primary => |*primary| try primary.clone(allocator),
            .abstraction => |*abstraction| try abstraction.clone(allocator),
            .application => |*application| try application.clone(allocator),
            .let_in => |*let_in| try let_in.clone(allocator),
            .let_rec_in => |*let_rec_in| try let_rec_in.clone(allocator),
            .if_then_else => |*if_then_else| try if_then_else.clone(allocator),
        };
    }

    pub fn format(
        self: *Node,
        comptime fmt: []const u8,
        options: FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.*) {
            .program => |program| if (program.expression) |expression|
                try expression.format(fmt, options, writer),
            .primary => |primary| {
                const operand = primary.operand;
                try writer.print("{s}", .{operand.lexeme});
            },
            .abstraction => |abstraction| {
                try writer.print("(λ{s}. ", .{abstraction.parameter.lexeme});
                try abstraction.body.format(fmt, options, writer);
                try writer.print(")", .{});
            },
            .application => |application| {
                try application.abstraction.format(fmt, options, writer);
                try writer.print(" ", .{});
                try application.argument.format(fmt, options, writer);
            },
            .let_in => |let_in| {
                try writer.print("\nlet ", .{});
                try let_in.name.format(fmt, options, writer);
                try writer.print(" = ", .{});
                try let_in.value.format(fmt, options, writer);
                try writer.print(" in ", .{});
                if (let_in.body.tag() != .let_in) try writer.print("\n  ", .{});
                try let_in.body.format(fmt, options, writer);
            },
            .let_rec_in => |let_rec_in| {
                try writer.print("\nlet rec ", .{});
                try let_rec_in.name.format(fmt, options, writer);
                try writer.print(" = ", .{});
                try let_rec_in.value.format(fmt, options, writer);
                try writer.print(" in ", .{});
                if (let_rec_in.body.tag() != .let_in) try writer.print("\n  ", .{});
                try let_rec_in.body.format(fmt, options, writer);
            },
            .if_then_else => |if_then_else| {
                try writer.print("if ", .{});
                try if_then_else.condition.format(fmt, options, writer);
                try writer.print(" then ", .{});
                try if_then_else.consequent.format(fmt, options, writer);
                try writer.print(" else ", .{});
                try if_then_else.alternate.format(fmt, options, writer);
            },
        }
    }

    pub fn equal(node_a: *Node, node_b: *Node) bool {
        if (node_a.tag() != node_b.tag()) return false;
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
            .abstraction => |a| {
                const b = node_b.abstraction;
                return a.parameter.equal(b.parameter) and a.body.equal(b.body);
            },
            .application => |a| {
                const b = node_b.application;
                return a.abstraction.equal(b.abstraction) and a.argument.equal(b.argument);
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
