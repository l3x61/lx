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
    string: *String,
    native: Native,
    closure: *Closure,

    pub const Tag = enum {
        free,
        boolean,
        number,
        string,
        native,
        closure,

        pub fn format(self: Tag, writer: anytype) !void {
            const name = switch (self) {
                .free => "Free",
                .boolean => "Boolean",
                .number => "Number",
                .string => "String",
                .native => "Native",
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
        bytes: []u8,

        pub fn deinit(self: *String, gpa: Allocator) void {
            gpa.free(self.bytes);
            gpa.destroy(self);
        }

        pub fn init(gpa: Allocator, literal: []const u8) !Value {
            const str = try gpa.create(String);
            errdefer gpa.destroy(str);
            const bytes = try gpa.dupe(u8, literal);
            errdefer gpa.free(bytes);
            str.* = .{ .bytes = bytes };
            return Value{ .string = str };
        }

        pub fn fromOwned(gpa: Allocator, owned: []u8) !Value {
            const str = try gpa.create(String);
            errdefer gpa.destroy(str);
            str.* = .{ .bytes = owned };
            return Value{ .string = str };
        }
    };

    pub const Native = struct {
        name: []const u8,
        function: *const fn (argument: Value, env: *Environment, capture_env: ?*Environment) anyerror!Value,
        capture_env: ?*Environment,

        pub fn init(
            name: []const u8,
            function: fn (argument: Value, env: *Environment, capture_env: ?*Environment) anyerror!Value,
            capture_env: ?*Environment,
        ) Value {
            return Value{ .native = Native{ .name = name, .function = function, .capture_env = capture_env } };
        }
    };

    pub const Closure = struct {
        parameter: []const u8,
        body: *Node,
        env: *Environment,

        pub fn init(
            gpa: Allocator,
            function: Node.Function,
            env: *Environment,
        ) !Value {
            const closure = try gpa.create(Closure);
            closure.* = Closure{
                .parameter = function.parameter.lexeme,
                .body = function.body,
                .env = env,
            };
            return .{ .closure = closure };
        }

        pub fn deinit(self: *Closure, gpa: Allocator) void {
            gpa.destroy(self);
        }
    };

    pub fn deinit(self: *Value, gpa: Allocator) void {
        return switch (self.*) {
            .string => |str| str.deinit(gpa),
            .closure => |closure| closure.deinit(gpa),
            .native => |native| if (native.capture_env) |env| env.deinit(),
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
            .string => |str| str.bytes,
            else => null,
        };
    }

    pub fn asNative(self: Value) ?Native {
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
                    string.bytes,
                    ansi.reset,
                });
            },
            .native => |native| {
                try writer.print("{s}{s}{s}", .{
                    ansi.magenta,
                    native.name,
                    ansi.reset,
                });
            },
            .closure => |closure| {
                var env = closure.env;

                while (env.parent) |parent| : (env = parent) {
                    var it = env.bindings.iterator();
                    while (it.next()) |entry| {
                        try writer.print(ansi.dim ++ " {s} = ", .{entry.key_ptr.*});

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

                        try writer.print("\n" ++ ansi.reset, .{});
                    }
                }

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
            .free => true,
            .boolean => |boolean| boolean == other.boolean,
            .number => |number| number == other.number,
            .string => |string| mem.eql(u8, string.bytes, other.string.bytes),
            .native => |native| native.function == other.native.function,
            .closure => |closure| closure == other.closure,
        };
    }
};
