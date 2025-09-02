const std = @import("std");
const Allocator = std.mem.Allocator;
const parseFloat = std.fmt.parseFloat;
const FormatOptions = std.fmt.FormatOptions;
const print = std.debug.print;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;

// TODO: rename void to undefined/uninitialized or maybe free
// TODO: string type
// TODO: array type
// TODO: table type
pub const Value = union(Tag) {
    void: void,
    null: void,
    boolean: bool,
    number: f64,
    builtin: Builtin,
    closure: *Closure,

    pub const Tag = enum {
        void,
        null,
        boolean,
        number,
        builtin,
        closure,

        pub fn format(self: Tag, writer: anytype) !void {
            try writer.print("{s}", .{@tagName(self)});
        }
    };

    pub fn tag(self: Value) Tag {
        return @as(Tag, self);
    }

    pub fn init() Value {
        return Value{ .void = {} };
    }

    pub const Null = struct {
        pub fn init() Value {
            return Value{ .null = {} };
        }
    };

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

        pub fn init(
            ator: Allocator,
            function: Node.Function,
            env: *Environment,
        ) !Value {
            const closure = try ator.create(Closure);
            closure.* = Closure{
                .parameter = function.parameter.lexeme,
                .body = function.body,
                .env = env,
            };
            return Value{ .closure = closure };
        }

        pub fn deinit(self: *Closure, ator: Allocator) void {
            ator.destroy(self);
        }
    };

    pub fn deinit(self: *Value, ator: Allocator) void {
        return switch (self.*) {
            .closure => |closure| closure.deinit(ator),
            .builtin => |builtin| if (builtin.capture_env) |env| env.deinitSelf(),
            else => {},
        };
    }

    pub fn isVoid(self: *const Value) bool {
        return self.tag() == .void;
    }

    pub fn asBoolean(self: *const Value) ?bool {
        return switch (self.*) {
            .null => false,
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
            .void => {
                try writer.print("{s}void{s}", .{
                    ansi.dim,
                    ansi.reset,
                });
            },
            .null => {
                try writer.print("{s}null{s}", .{
                    ansi.blue,
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
            },
        }
    }

    pub fn equal(self: Value, other: Value) bool {
        if (self.tag() != other.tag()) {
            return false;
        }

        return switch (self) {
            .void => true,
            .null => true,
            .boolean => |boolean| boolean == other.asBoolean().?,
            .number => |number| number == other.asNumber().?,
            .builtin => |builtin| builtin.function == other.asBuiltin().?.function,
            .closure => |closure| closure == other.asClosure().?,
        };
    }
};
