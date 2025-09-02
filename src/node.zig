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
    application,
    binding,
    selection,

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
    application: Application,
    binding: Binding,
    selection: Selection,

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

    pub const Binding = struct {
        name: Token,
        value: *Node,
        body: *Node,

        pub fn init(ator: Allocator, name: Token, value: *Node, body: *Node) !*Node {
            const node = try ator.create(Node);
            node.* = Node{ .binding = .{ .name = name, .value = value, .body = body } };
            return node;
        }

        pub fn deinit(self: *Binding, ator: Allocator) void {
            self.value.deinit(ator);
            self.body.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("binding", self)));
        }

        pub fn clone(self: *Binding, ator: Allocator) !*Node {
            const value = try self.value.clone(ator);
            const body = try self.body.clone(ator);
            return try Binding.init(ator, self.name, value, body);
        }
    };

    pub const Selection = struct {
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
            node.* = Node{ .selection = .{
                .condition = condition,
                .consequent = consequent,
                .alternate = alternate,
            } };
            return node;
        }

        pub fn deinit(self: *Selection, ator: Allocator) void {
            self.condition.deinit(ator);
            self.consequent.deinit(ator);
            self.alternate.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("selection", self)));
        }

        pub fn clone(self: *Selection, ator: Allocator) !*Node {
            const condition = try self.condition.clone(ator);
            const consequent = try self.consequent.clone(ator);
            const alternate = try self.alternate.clone(ator);
            return try Selection.init(ator, condition, consequent, alternate);
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

    pub const Application = struct {
        function: *Node,
        argument: *Node,

        pub fn init(
            ator: Allocator,
            function: *Node,
            argument: *Node,
        ) !*Node {
            const node = try ator.create(Node);
            node.* = Node{
                .application = .{
                    .function = function,
                    .argument = argument,
                },
            };
            return node;
        }

        pub fn deinit(self: *Application, ator: Allocator) void {
            self.function.deinit(ator);
            self.argument.deinit(ator);
            ator.destroy(@as(*Node, @fieldParentPtr("application", self)));
        }

        pub fn clone(self: *Application, ator: Allocator) !*Node {
            const function = try self.function.clone(ator);
            const argument = try self.argument.clone(ator);
            return try Application.init(ator, function, argument);
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
            .application => |*application| application.deinit(ator),
            .binding => |*binding| binding.deinit(ator),
            .selection => |*selection| selection.deinit(ator),
        }
    }

    pub fn clone(self: *Node, ator: Allocator) anyerror!*Node {
        return switch (self.*) {
            .program => |*program| try program.clone(ator),
            .primary => |*primary| try primary.clone(ator),
            .binary => |*binary| try binary.clone(ator),
            .function => |*function| try function.clone(ator),
            .application => |*application| try application.clone(ator),
            .binding => |*let_in| try let_in.clone(ator),
            .selection => |*selection| try selection.clone(ator),
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
                try writer.print("(", .{});
                try binary.left.format(writer);
                try writer.print(" {s} ", .{binary.operator.lexeme});
                try binary.right.format(writer);
                try writer.print(")", .{});
            },
            .function => |function| {
                try writer.print("(λ{s}. ", .{function.parameter.lexeme});
                try function.body.format(writer);
                try writer.print(")", .{});
            },
            .application => |application| {
                try application.function.format(writer);
                try writer.print(" ", .{});
                try application.argument.format(writer);
            },
            .binding => |let_in| {
                try writer.print("\nlet ", .{});
                try let_in.name.format(writer);
                try writer.print(" = ", .{});
                try let_in.value.format(writer);
                try writer.print(" in ", .{});
                if (let_in.body.tag() != .binding) {
                    try writer.print("\n  ", .{});
                }
                try let_in.body.format(writer);
            },
            .selection => |selection| {
                try writer.print("if ", .{});
                try selection.condition.format(writer);
                try writer.print(" then ", .{});
                try selection.consequent.format(writer);
                try writer.print(" else ", .{});
                try selection.alternate.format(writer);
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
            .application => |a| {
                const b = node_b.application;
                return a.function.equal(b.function) and a.argument.equal(b.argument);
            },
            .binding => |a| {
                const b = node_b.binding;
                return a.name.equal(b.name) and a.value.equal(b.value) and a.body.equal(b.body);
            },
            .selection => |a| {
                const b = node_b.selection;
                return a.condition.equal(b.condition) and
                    a.consequent.equal(b.consequent) and
                    a.alternate.equal(b.alternate);
            },
        };
    }
};
