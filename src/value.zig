const std = @import("std");
const Allocator = std.mem.Allocator;
const parseFloat = std.fmt.parseFloat;
const FormatOptions = std.fmt.FormatOptions;
const print = std.debug.print;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;

pub const Value = union(Tag) {
    null: void,
    boolean: bool,
    number: Number,
    closure: *Closure,

    pub const Tag = enum {
        null,
        boolean,
        number,
        closure,

        pub fn format(self: Tag, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
            try writer.print("{s}", .{@tagName(self)});
        }
    };

    fn tag(self: Value) Tag {
        return @as(Tag, self);
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
        value: f64,

        pub fn init(value: f64) Value {
            return Value{ .number = Number{ .value = value } };
        }

        pub fn parse(lexeme: []const u8) !Value {
            const value = try parseFloat(f64, lexeme);
            return Value{ .number = Number{ .value = value } };
        }
    };

    pub const Closure = struct {
        parameter: []const u8,
        body: *Node,
        env: *Environment,

        pub fn init(
            allocator: Allocator,
            function: Node.Abstraction,
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
            else => {},
        };
    }

    pub fn asNumber(self: *const Value) ?Number {
        return switch (self.*) {
            .number => |number| number,
            else => null,
        };
    }

    pub fn asBoolean(self: *const Value) ?bool {
        return switch (self.*) {
            .null => false,
            .number => |number| number.value != 0,
            .boolean => |boolean| boolean,
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
            .null => try writer.print("null", .{}),
            .boolean => |boolean| try writer.print("{}", .{boolean}),
            .number => |number| try writer.print("{d}", .{number.value}),
            .closure => |closure| try writer.print("λ@0x{x} {s}", .{
                @intFromPtr(closure),
                closure.body,
            }),
        }
    }

    pub fn equal(self: Value, other: Value) bool {
        if (self.tag() != other.tag()) return false;

        return switch (self) {
            .null => true,
            .boolean => |boolean| boolean == other.asBoolean().?,
            .number => |number| number.value == other.asNumber().?.value,
            .closure => |closure| closure == other.asFunction().?,
        };
    }
};
