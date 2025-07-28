const std = @import("std");
const Allocator = std.mem.Allocator;
const parseFloat = std.fmt.parseFloat;
const FormatOptions = std.fmt.FormatOptions;

const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;

pub const Tag = enum {
    null,
    number,
    function,

    pub fn format(self: Tag, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Value = union(Tag) {
    null: void,
    number: Number,
    function: *Function,

    fn tag(self: Value) Tag {
        return @as(Tag, self);
    }

    pub const Null = struct {
        pub fn init() Value {
            return Value{ .null = {} };
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

    pub const Function = struct {
        parameter: []const u8,
        body: *Node,
        closure: *Environment,

        pub fn init(
            allocator: Allocator,
            function: Node.Abstraction,
            env: *Environment,
        ) !Value {
            const func = try allocator.create(Function);
            func.* = Function{
                .parameter = function.parameter.lexeme,
                .body = function.body,
                .closure = env,
            };
            return Value{ .function = func };
        }

        pub fn deinit(self: *Function, allocator: Allocator) void {
            allocator.destroy(self);
        }
    };

    pub fn deinit(self: *Value, allocator: Allocator) void {
        return switch (self.*) {
            .function => |function| function.deinit(allocator),
            else => {},
        };
    }

    pub fn asNumber(self: *const Value) ?Number {
        return switch (self.*) {
            .number => |number| number,
            else => null,
        };
    }

    pub fn asFunction(self: Value) ?*Function {
        return switch (self) {
            .function => |function| function,
            else => null,
        };
    }

    pub fn format(self: Value, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        switch (self) {
            .null => try writer.print("null", .{}),
            .number => |number| try writer.print("{d}", .{number.value}),
            .function => |*function| try writer.print("λ@{x}", .{@intFromPtr(function)}),
        }
    }

    pub fn equal(self: Value, other: Value) bool {
        if (self.tag() != other.tag()) return false;

        return switch (self) {
            .null => true,
            .number => |number| number.value == other.asNumber().?.value,
            .function => |function| function == other.asFunction().?,
        };
    }
};
