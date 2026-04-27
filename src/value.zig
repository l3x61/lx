const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Environment = @import("Environment.zig");
const Clause = @import("node.zig").Clause;
const Token = @import("Token.zig");

pub const Value = union(Tag) {
    unit: void,
    boolean: bool,
    integer: i64,
    string: *String,
    list: *List,
    tuple: *Tuple,
    map: *Map,
    native: *Native,
    closure: *Closure,

    pub const Tag = enum {
        unit,
        boolean,
        integer,
        string,
        list,
        tuple,
        map,
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

    pub const Integer = struct {
        pub fn init(value: i64) Value {
            return .{ .integer = value };
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

    pub const Tuple = struct {
        items: []Value,

        pub fn initOwned(gpa: Allocator, items: []Value) !Value {
            const ptr = try gpa.create(Tuple);
            errdefer gpa.destroy(ptr);
            ptr.* = .{ .items = items };
            return .{ .tuple = ptr };
        }

        pub fn init(gpa: Allocator, items: []const Value) !Value {
            return initOwned(gpa, try gpa.dupe(Value, items));
        }

        pub fn deinit(self: *Tuple, gpa: Allocator) void {
            gpa.free(self.items);
            gpa.destroy(self);
        }
    };

    pub const Map = struct {
        entries: []Entry,

        pub const Entry = struct {
            key: Value,
            value: Value,
        };

        pub fn initOwned(gpa: Allocator, entries: []Entry) !Value {
            const ptr = try gpa.create(Map);
            errdefer gpa.destroy(ptr);
            ptr.* = .{ .entries = entries };
            return .{ .map = ptr };
        }

        pub fn init(gpa: Allocator, entries: []const Entry) !Value {
            return initOwned(gpa, try gpa.dupe(Entry, entries));
        }

        pub fn deinit(self: *Map, gpa: Allocator) void {
            gpa.free(self.entries);
            gpa.destroy(self);
        }

        pub fn findIndex(self: *const Map, key: Value) ?usize {
            for (self.entries, 0..) |entry, index| {
                if (entry.key.equal(key)) return index;
            }
            return null;
        }

        pub fn findStringIndex(self: *const Map, key: []const u8) ?usize {
            for (self.entries, 0..) |entry, index| {
                const bytes = entry.key.asString() orelse continue;
                if (std.mem.eql(u8, bytes, key)) return index;
            }
            return null;
        }
    };

    pub const NativeContext = struct {
        gpa: Allocator,
        io: Io,
        tracker: *anyopaque,
        trackFn: *const fn (*anyopaque, Value) anyerror!void,

        pub fn allocator(self: NativeContext) Allocator {
            return self.gpa;
        }

        pub fn track(self: NativeContext, value: Value) anyerror!void {
            try self.trackFn(self.tracker, value);
        }
    };

    pub const Native = struct {
        name: []const u8,
        function: *const fn (context: NativeContext, argument: Value) anyerror!Value,

        pub fn init(
            gpa: Allocator,
            name: []const u8,
            function: *const fn (context: NativeContext, argument: Value) anyerror!Value,
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
        clauses: []const *Clause,
        env: *Environment,

        pub fn init(
            gpa: Allocator,
            clauses: []const *Clause,
            env: *Environment,
        ) !Value {
            const ptr = try gpa.create(Closure);
            errdefer gpa.destroy(ptr);
            ptr.* = .{
                .clauses = clauses,
                .env = env,
            };
            return .{ .closure = ptr };
        }
    };

    pub fn deinit(self: Value, gpa: Allocator) void {
        switch (self) {
            .string => |string| string.deinit(gpa),
            .list => |list| list.deinit(gpa),
            .tuple => |tuple| tuple.deinit(gpa),
            .map => |map| map.deinit(gpa),
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

    pub fn asInteger(self: Value) ?i64 {
        return switch (self) {
            .integer => |i| i,
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

    pub fn asTuple(self: Value) ?*Tuple {
        return switch (self) {
            .tuple => |tuple| tuple,
            else => null,
        };
    }

    pub fn asMap(self: Value) ?*Map {
        return switch (self) {
            .map => |map| map,
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
            .integer => |value| switch (right) {
                .integer => |other| value == other,
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
            .tuple => |value| switch (right) {
                .tuple => |other| blk: {
                    if (value.items.len != other.items.len) break :blk false;
                    for (value.items, other.items) |lhs, rhs| {
                        if (!lhs.equal(rhs)) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
            .map => |value| switch (right) {
                .map => |other| blk: {
                    if (value.entries.len != other.entries.len) break :blk false;
                    for (value.entries) |entry| {
                        const index = other.findIndex(entry.key) orelse break :blk false;
                        if (!entry.value.equal(other.entries[index].value)) break :blk false;
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
            .integer => |i| try writer.print("{d}", .{i}),
            .string => |string| try writer.print("\"{s}\"", .{string.bytes}),
            .list => |list| {
                try writer.writeByte('[');
                for (list.items, 0..) |item, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try item.write(writer);
                }
                try writer.writeByte(']');
            },
            .tuple => |tuple| {
                try writer.writeByte('(');
                for (tuple.items, 0..) |item, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try item.write(writer);
                }
                try writer.writeByte(')');
            },
            .map => |map| {
                try writer.writeByte('{');
                for (map.entries, 0..) |entry, index| {
                    if (index != 0) try writer.writeAll(", ");
                    try entry.key.write(writer);
                    try writer.writeAll(": ");
                    try entry.value.write(writer);
                }
                try writer.writeByte('}');
            },
            .native => |native| try writer.print("<native {s}>", .{native.name}),
            .closure => try writer.writeAll("<function>"),
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
