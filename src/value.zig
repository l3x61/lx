const std = @import("std");
const Allocator = std.mem.Allocator;
const parseFloat = std.fmt.parseFloat;
const FormatOptions = std.fmt.FormatOptions;
const print = std.debug.print;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;

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

        pub fn format(self: Tag, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
            try writer.print("{s}", .{@tagName(self)});
        }
    };

    fn tag(self: Value) Tag {
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
            allocator: Allocator,
            function: Node.Function,
            env: *Environment,
        ) !Value {
            const closure = try allocator.create(Closure);
            closure.* = Closure{
                .parameter = function.parameter.lexeme,
                .body = function.body,
                .env = env,
            };
            return Value{ .closure = closure };
        }

        pub fn deinit(self: *Closure, allocator: Allocator) void {
            allocator.destroy(self);
        }
    };

    pub fn deinit(self: *Value, allocator: Allocator) void {
        return switch (self.*) {
            .closure => |closure| closure.deinit(allocator),
            .builtin => |builtin| if (builtin.capture_env) |ce| ce.deinitSelf(allocator),
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

    pub fn asFunction(self: Value) ?*Closure {
        return switch (self) {
            .closure => |closure| closure,
            else => null,
        };
    }

    pub fn format(self: Value, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        switch (self) {
            .void => try writer.print("<void>", .{}),
            .null => try writer.print("null", .{}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .number => |number| try writer.print("{d}", .{number}),
            .builtin => |builtin| try writer.print("<{s}>", .{builtin.name}),
            .closure => |closure| try writer.print("<λ{s}. {s}>", .{ closure.parameter, closure.body }),
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
            .closure => |closure| closure == other.asFunction().?,
        };
    }
};
