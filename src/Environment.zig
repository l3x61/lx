const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringArrayHashMap;
const testing = std.testing;
const print = std.debug.print;
const expect = testing.expect;

const ansi = @import("ansi.zig");
const Value = @import("value.zig").Value;

const Environment = @This();

parent: ?*Environment,
record: StringHashMap(Value),

pub fn init(allocator: Allocator, parent: ?*Environment) !*Environment {
    const self = try allocator.create(Environment);
    self.* = Environment{
        .parent = parent,
        .record = StringHashMap(Value).init(allocator),
    };
    return self;
}

pub fn deinitSelf(self: *Environment, allocator: Allocator) void {
    var it = self.record.iterator();
    while (it.next()) |entry| allocator.free(entry.key_ptr.*);
    self.record.deinit();
    allocator.destroy(self);
}

pub fn deinitAll(self: *Environment, allocator: Allocator) void {
    if (self.parent) |parent| parent.deinitAll(allocator);
    self.deinitSelf(allocator);
}

pub fn define(self: *Environment, allocator: Allocator, key: []const u8, value: Value) !void {
    const new_key = try allocator.dupe(u8, key);
    errdefer allocator.free(new_key);

    const entry = try self.record.getOrPut(new_key);
    if (entry.found_existing) return error.AlreadyDefined;
    entry.value_ptr.* = value;
}

pub fn lookup(self: *Environment, key: []const u8) ?Value {
    if (self.record.get(key)) |value| return value;
    if (self.parent) |parent| return parent.lookup(key);
    return null;
}

pub fn debug(self: *Environment) void {
    if (self.record.unmanaged.entries.len == 0) {
        print("{s}empty{s}\n", .{ ansi.dimmed, ansi.reset });
    }
    self._debug(0);
}

fn _debug(self: *Environment, depth: usize) void {
    var it = self.record.iterator();
    while (it.next()) |entry|
        print("[{d}] {s} = {s}\n", .{ depth, entry.key_ptr.*, entry.value_ptr.* });
    if (self.parent) |parent| parent._debug(depth + 1);
}

test "define and lookup variable" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll(testing.allocator);
    const x = Value.Number.init(123);
    try env.define(testing.allocator, "x", x);

    try expect(env.lookup("x").?.equal(x));
    try expect(env.lookup("y") == null);
}

test "lookup variable via parent" {
    const parent = try Environment.init(testing.allocator, null);
    const x = Value.Number.init(42);
    try parent.define(testing.allocator, "x", x);

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll(testing.allocator);

    try expect(child.lookup("x").?.equal(x));
    try expect(child.lookup("y") == null);
}

test "shadowing" {
    const parent = try Environment.init(testing.allocator, null);
    const x_parent = Value.Number.init(42);
    try parent.define(testing.allocator, "x", x_parent);

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll(testing.allocator);
    const x_child = Value.Number.init(99);
    try child.define(testing.allocator, "x", x_child);

    try expect(child.lookup("x").?.equal(x_child));
}
