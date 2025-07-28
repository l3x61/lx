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
    function,
    application,

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
    function: Function,
    application: Application,

    fn tag(self: Node) Tag {
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
    };

    pub const Function = struct {
        parameter: Token,
        body: *Node,

        pub fn init(allocator: Allocator, parameter: Token, body: *Node) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .function = .{ .parameter = parameter, .body = body },
            };
            return node;
        }

        fn deinit(self: *Function, allocator: Allocator) void {
            self.body.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("function", self)));
        }
    };

    pub const Application = struct {
        function: *Node,
        argument: *Node,

        pub fn init(
            allocator: Allocator,
            function: *Node,
            argument: *Node,
        ) !*Node {
            const node = try allocator.create(Node);
            node.* = Node{
                .application = .{
                    .function = function,
                    .argument = argument,
                },
            };
            return node;
        }

        pub fn deinit(self: *Application, allocator: Allocator) void {
            self.function.deinit(allocator);
            self.argument.deinit(allocator);
            allocator.destroy(@as(*Node, @fieldParentPtr("application", self)));
        }
    };

    pub fn deinit(self: *Node, allocator: Allocator) void {
        switch (self.*) {
            .program => |*program| program.deinit(allocator),
            .primary => |*primary| primary.deinit(allocator),
            .function => |*function| function.deinit(allocator),
            .application => |*application| application.deinit(allocator),
        }
    }

    pub fn debug(self: *Node, allocator: Allocator) !void {
        var prefix = String.init(allocator);
        defer prefix.deinit();
        try self._debug(&prefix, true);
    }

    fn _debug(self: *Node, prefix: *String, is_last: bool) !void {
        print(ansi.dimmed ++ "{s}", .{prefix.items});
        var _prefix = try prefix.clone();
        defer _prefix.deinit();
        if (!is_last) {
            print("├── ", .{});
            try _prefix.appendSlice("│   ");
        } else {
            if (@as(Tag, self.*) != .program) {
                print("└── ", .{});
                try _prefix.appendSlice("    ");
            }
        }
        print(ansi.reset, .{});

        switch (self.*) {
            .program => |program| {
                print("{s}\n", .{@as(Tag, self.*)});
                if (program.expression) |expression| {
                    try expression._debug(&_prefix, true);
                }
            },
            .primary => |primary| {
                const operand = primary.operand;
                print("{s} " ++ ansi.cyan ++ "{s}\n" ++ ansi.reset, .{
                    operand.tag,
                    operand.lexeme,
                });
            },
            .function => |function| {
                print("{s} " ++ ansi.magenta ++ "{s}\n" ++ ansi.reset, .{
                    @as(Tag, self.*),
                    function.parameter.lexeme,
                });
                try function.body._debug(&_prefix, true);
            },
            .application => |application| {
                print("{s}\n", .{@as(Tag, self.*)});
                try application.function._debug(&_prefix, false);
                try application.argument._debug(&_prefix, true);
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
            .function => |a| {
                const b = node_b.function;
                return a.parameter.equal(b.parameter) and
                    a.body.equal(b.body);
            },
            .application => |a| {
                const b = node_b.application;
                return a.function.equal(b.function) and
                    a.argument.equal(b.argument);
            },
        };
    }
};
