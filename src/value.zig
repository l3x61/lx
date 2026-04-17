const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Environment = @import("Environment.zig");
const FunctionBody = @import("node.zig").FunctionBody;
const Token = @import("Token.zig");

pub const Value = union(Tag) {
    unit: void,
    boolean: bool,
    number: f64,
    string: *String,
    list: *List,
    native: *Native,
    closure: *Closure,

    pub const Tag = enum {
        unit,
        boolean,
        number,
        string,
        list,
        native,
        closure,

        pub fn format(self: Tag, writer: anytype) !void {
            try writer.writeAll(@tagName(self));
        }
    };

    pub const Unit = struct {
        pub fn init() Value {
            return .{ .unit = {} };
        }
    };

    pub const Boolean = struct {
        pub fn init(value: bool) Value {
            return .{ .boolean = value };
        }
    };

    pub const Number = struct {
        pub fn init(value: f64) Value {
            return .{ .number = value };
        }
    };

    pub const String = struct {
        bytes: []u8,

        pub fn initOwned(gpa: Allocator, bytes: []u8) !Value {
            const ptr = try gpa.create(String);
            errdefer gpa.destroy(ptr);
            ptr.* = .{ .bytes = bytes };
            return .{ .string = ptr };
        }

        pub fn init(gpa: Allocator, bytes: []const u8) !Value {
            return initOwned(gpa, try gpa.dupe(u8, bytes));
        }

        pub fn deinit(self: *String, gpa: Allocator) void {
            gpa.free(self.bytes);
            gpa.destroy(self);
        }
    };

    pub const List = struct {
        items: []Value,

        pub fn initOwned(gpa: Allocator, items: []Value) !Value {
            const ptr = try gpa.create(List);
            errdefer gpa.destroy(ptr);
            ptr.* = .{ .items = items };
            return .{ .list = ptr };
        }

        pub fn init(gpa: Allocator, items: []const Value) !Value {
            return initOwned(gpa, try gpa.dupe(Value, items));
        }

        pub fn deinit(self: *List, gpa: Allocator) void {
            gpa.free(self.items);
            gpa.destroy(self);
        }
    };

    pub const Native = struct {
        name: []const u8,
        function: *const fn (io: Io, arguments: []const Value) anyerror!Value,

        pub fn init(
            gpa: Allocator,
            name: []const u8,
            function: *const fn (io: Io, arguments: []const Value) anyerror!Value,
        ) !Value {
            const ptr = try gpa.create(Native);
            errdefer gpa.destroy(ptr);
            ptr.* = .{
                .name = name,
                .function = function,
            };
            return .{ .native = ptr };
        }

        pub fn deinit(self: *Native, gpa: Allocator) void {
            gpa.destroy(self);
        }
    };

    pub const Closure = struct {
        parameters: []const Token,
        body: FunctionBody,
        env: *Environment,

        pub fn init(
            gpa: Allocator,
            parameters: []const Token,
            body: FunctionBody,
            env: *Environment,
        ) !Value {
            const ptr = try gpa.create(Closure);
            errdefer gpa.destroy(ptr);
            ptr.* = .{
                .parameters = parameters,
                .body = body,
                .env = env,
            };
            return .{ .closure = ptr };
        }
    };

    pub fn deinit(self: Value, gpa: Allocator) void {
        switch (self) {
            .string => |string| string.deinit(gpa),
            .list => |list| list.deinit(gpa),
            .native => |native| native.deinit(gpa),
            .closure => |closure| gpa.destroy(closure),
            else => {},
        }
    }

    pub fn asBoolean(self: Value) ?bool {
        return switch (self) {
            .boolean => |boolean| boolean,
            else => null,
        };
    }

    pub fn asNumber(self: Value) ?f64 {
        return switch (self) {
            .number => |number| number,
            else => null,
        };
    }

    pub fn asString(self: Value) ?[]const u8 {
        return switch (self) {
            .string => |string| string.bytes,
            else => null,
        };
    }

    pub fn asList(self: Value) ?*List {
        return switch (self) {
            .list => |list| list,
            else => null,
        };
    }

    pub fn asNative(self: Value) ?*Native {
        return switch (self) {
            .native => |native| native,
            else => null,
        };
    }

    pub fn asClosure(self: Value) ?*Closure {
        return switch (self) {
            .closure => |closure| closure,
            else => null,
        };
    }

    pub fn equal(left: Value, right: Value) bool {
        return switch (left) {
            .unit => switch (right) {
                .unit => true,
                else => false,
            },
            .boolean => |value| switch (right) {
                .boolean => |other| value == other,
                else => false,
            },
            .number => |value| switch (right) {
                .number => |other| value == other,
                else => false,
            },
            .string => |value| switch (right) {
                .string => |other| std.mem.eql(u8, value.bytes, other.bytes),
                else => false,
            },
            .list => |value| switch (right) {
                .list => |other| blk: {
                    if (value.items.len != other.items.len) break :blk false;
                    for (value.items, other.items) |lhs, rhs| {
                        if (!lhs.equal(rhs)) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
            .native => |value| switch (right) {
                .native => |other| value == other,
                else => false,
            },
            .closure => |value| switch (right) {
                .closure => |other| value == other,
                else => false,
            },
        };
    }

    pub fn write(self: Value, writer: anytype) !void {
        switch (self) {
            .unit => try writer.writeAll("()"),
            .boolean => |boolean| try writer.writeAll(if (boolean) "true" else "false"),
            .number => |number| try writer.print("{d}", .{number}),
            .string => |string| try writer.print("\"{s}\"", .{string.bytes}),
            .list => |list| {
                try writer.writeByte('[');
                for (list.items, 0..) |item, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try item.write(writer);
                }
                try writer.writeByte(']');
            },
            .native => |native| try writer.print("<native {s}>", .{native.name}),
            .closure => |closure| {
                try writer.writeByte('(');
                for (closure.parameters, 0..) |parameter, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try writer.writeAll(parameter.lexeme);
                }
                try writer.writeAll(") { ... }");
            },
        }
    }

    pub fn display(self: Value, writer: anytype) !void {
        switch (self) {
            .string => |string| try writer.writeAll(string.bytes),
            else => try self.write(writer),
        }
    }

    pub fn format(self: Value, writer: anytype) !void {
        try self.write(writer);
    }
};
