const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const parseFloat = std.fmt.parseFloat;
const print = std.debug.print;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;

// TODO: array type
// TODO: table type
pub const Value = union(Tag) {
    free: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    builtin: Builtin,
    closure: *Closure,

    pub const Tag = enum {
        free,
        boolean,
        number,
        string,
        builtin,
        closure,

        pub fn format(self: Tag, writer: anytype) !void {
            const name = switch (self) {
                .free => "Free",
                .boolean => "Boolean",
                .number => "Number",
                .string => "String",
                .builtin => "Builtin",
                .closure => "Closure",
            };
            try writer.print("{s}", .{name});
        }
    };

    pub fn tag(self: Value) Tag {
        return @as(Tag, self);
    }

    pub fn init() Value {
        return Value{ .free = {} };
    }

    pub const Boolean = struct {
        pub fn init(value: bool) Value {
            return Value{ .boolean = value };
        }
    };

    pub const Number = struct {
        pub fn init(value: f64) Value {
            return Value{ .number = value };
        }

        pub fn parse(lexeme: []const u8) !Value {
            const value = try parseFloat(f64, lexeme);
            return Value{ .number = value };
        }
    };

    pub const String = struct {
        pub fn init(gpa: Allocator, literal: []const u8) !Value {
            const string = try gpa.alloc(u8, literal.len);
            @memcpy(string, literal);
            return Value{ .string = string };
        }
    };

    pub const Builtin = struct {
        name: []const u8,
        function: *const fn (argument: Value, env: *Environment, capture_env: ?*Environment) anyerror!Value,
        capture_env: ?*Environment,

        pub fn init(
            name: []const u8,
            function: fn (argument: Value, env: *Environment, capture_env: ?*Environment) anyerror!Value,
            capture_env: ?*Environment,
        ) Value {
            return Value{ .builtin = Builtin{ .name = name, .function = function, .capture_env = capture_env } };
        }
    };

    pub const Closure = struct {
        parameter: []const u8,
        body: *Node,
        env: *Environment,
        lexemes: ArrayList([]u8),

        pub fn init(
            gpa: Allocator,
            function: Node.Function,
            env: *Environment,
        ) !Value {
            const body = try function.body.clone(gpa);

            var closure = try gpa.create(Closure);
            closure.* = Closure{
                .parameter = undefined,
                .body = body,
                .env = env,
                .lexemes = .empty,
            };

            const param = try gpa.dupe(u8, function.parameter.lexeme);
            errdefer gpa.free(param);
            closure.parameter = param;
            try closure.lexemes.append(gpa, param);

            try cloneLexemes(gpa, body, &closure.lexemes);

            return Value{ .closure = closure };
        }

        pub fn deinit(self: *Closure, gpa: Allocator) void {
            for (self.lexemes.items) |str| gpa.free(str);
            self.lexemes.deinit(gpa);

            self.body.deinit(gpa);

            gpa.destroy(self);
        }
    };

    pub fn deinit(self: *Value, gpa: Allocator) void {
        return switch (self.*) {
            .string => |string| gpa.free(string),
            .closure => |closure| closure.deinit(gpa),
            .builtin => |builtin| if (builtin.capture_env) |env| env.deinit(),
            else => {},
        };
    }

    pub fn isFree(self: *const Value) bool {
        return self.tag() == .free;
    }

    pub fn asBoolean(self: *const Value) ?bool {
        return switch (self.*) {
            .boolean => |boolean| boolean,
            .number => |number| number != 0,
            else => null,
        };
    }

    pub fn asNumber(self: *const Value) ?f64 {
        return switch (self.*) {
            .number => |number| number,
            else => null,
        };
    }

    pub fn asString(self: *const Value) ?[]const u8 {
        return switch (self.*) {
            .string => |string| string,
            else => null,
        };
    }

    pub fn asBuiltin(self: Value) ?Builtin {
        return switch (self) {
            .builtin => |builtin| builtin,
            else => null,
        };
    }

    pub fn asClosure(self: Value) ?*Closure {
        return switch (self) {
            .closure => |closure| closure,
            else => null,
        };
    }

    pub fn format(self: Value, writer: anytype) !void {
        switch (self) {
            .free => {
                try writer.print("{s}free{s}", .{
                    ansi.dim,
                    ansi.reset,
                });
            },
            .boolean => |boolean| {
                try writer.print("{s}{any}{s}", .{
                    ansi.blue,
                    boolean,
                    ansi.reset,
                });
            },
            .number => |number| {
                try writer.print("{s}{d}{s}", .{
                    ansi.blue,
                    number,
                    ansi.reset,
                });
            },
            .string => |string| {
                try writer.print("{s}\"{s}\"{s}", .{
                    ansi.blue,
                    string,
                    ansi.reset,
                });
            },
            .builtin => |builtin| {
                try writer.print("{s}{s}{s}", .{
                    ansi.magenta,
                    builtin.name,
                    ansi.reset,
                });
            },
            .closure => |closure| {
                try writer.print("{s}λ{s}{s}{s}.{s} {f}", .{
                    ansi.red,
                    ansi.reset,
                    closure.parameter,
                    ansi.red,
                    ansi.reset,
                    closure.body,
                });

                var env = closure.env;
                var printed_any: bool = false;

                while (env.parent) |parent| : (env = parent) {
                    var it = env.bindings.iterator();
                    while (it.next()) |entry| {
                        if (!printed_any) {
                            try writer.print("\n", .{});
                            printed_any = true;
                        }

                        try writer.print(" {s} = ", .{entry.key_ptr.*});

                        if (entry.value_ptr.*) |value| {
                            switch (value) {
                                .closure => |inner| {
                                    try writer.print("{s}λ{s}{s}{s}.{s} {f}", .{
                                        ansi.red,
                                        ansi.reset,
                                        inner.parameter,
                                        ansi.red,
                                        ansi.reset,
                                        inner.body,
                                    });
                                },
                                else => try writer.print("{f}", .{value}),
                            }
                        } else {
                            const free = Value.init();
                            try writer.print("{f}", .{free});
                        }

                        try writer.print("\n", .{});
                    }
                }
            },
        }
    }

    pub fn equal(self: Value, other: Value) bool {
        if (self.tag() != other.tag()) {
            return false;
        }

        return switch (self) {
            .free => true,
            .boolean => |boolean| boolean == other.boolean,
            .number => |number| number == other.number,
            .string => |string| mem.eql(u8, string, other.string),
            .builtin => |builtin| builtin.function == other.builtin.function,
            .closure => |closure| closure == other.closure,
        };
    }
};

fn cloneLexemes(gpa: Allocator, node: *Node, lexemes: *ArrayList([]u8)) anyerror!void {
    switch (node.*) {
        .program => |*program| {
            if (program.expression) |expr| try cloneLexemes(gpa, expr, lexemes);
        },
        .primary => |*primary| {
            var token = &primary.operand;
            const lexeme = try gpa.dupe(u8, token.lexeme);
            try lexemes.append(gpa, lexeme);
            token.source = lexeme;
            token.lexeme = lexeme;
        },
        .binary => |*binary| {
            var token = &binary.operator;
            const lexeme = try gpa.dupe(u8, token.lexeme);
            try lexemes.append(gpa, lexeme);
            token.source = lexeme;
            token.lexeme = lexeme;
            try cloneLexemes(gpa, binary.left, lexemes);
            try cloneLexemes(gpa, binary.right, lexemes);
        },
        .function => |*function| {
            var token = &function.parameter;
            const lexeme = try gpa.dupe(u8, token.lexeme);
            try lexemes.append(gpa, lexeme);
            token.source = lexeme;
            token.lexeme = lexeme;
            try cloneLexemes(gpa, function.body, lexemes);
        },
        .application => |*application| {
            try cloneLexemes(gpa, application.function, lexemes);
            try cloneLexemes(gpa, application.argument, lexemes);
        },
        .binding => |*binding| {
            var token = &binding.name;
            const lexeme = try gpa.dupe(u8, token.lexeme);
            try lexemes.append(gpa, lexeme);
            token.source = lexeme;
            token.lexeme = lexeme;
            try cloneLexemes(gpa, binding.value, lexemes);
            try cloneLexemes(gpa, binding.body, lexemes);
        },
        .selection => |*selection| {
            try cloneLexemes(gpa, selection.condition, lexemes);
            try cloneLexemes(gpa, selection.consequent, lexemes);
            try cloneLexemes(gpa, selection.alternate, lexemes);
        },
    }
}
