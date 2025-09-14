const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringArrayHashMap;

const ansi = @import("ansi.zig");
const Value = @import("value.zig").Value;

const log = std.log.scoped(.env);
const Environment = @This();

gpa: Allocator,
parent: ?*Environment,
bindings: HashMap(?Value),

pub fn init(gpa: Allocator, parent: ?*Environment) !*Environment {
    const self = try gpa.create(Environment);
    self.* = Environment{
        .gpa = gpa,
        .parent = parent,
        .bindings = HashMap(?Value).init(gpa),
    };
    return self;
}

pub fn deinit(self: *Environment) void {
    var it = self.bindings.iterator();
    while (it.next()) |entry| {
        self.gpa.free(entry.key_ptr.*);
    }
    self.bindings.deinit();
    self.gpa.destroy(self);
}

pub fn deinitAll(self: *Environment) void {
    if (self.parent) |parent| {
        parent.deinitAll();
    }
    self.deinit();
}

pub fn bind(self: *Environment, key: []const u8, value: ?Value) !void {
    const new_key = try self.gpa.dupe(u8, key);
    errdefer self.gpa.free(new_key);

    const entry = try self.bindings.getOrPut(new_key);
    if (entry.found_existing) {
        log.err("{s} is already bound\n", .{key});
        return error.AlreadyDefined;
    }
    entry.value_ptr.* = value;
}

pub fn set(self: *Environment, key: []const u8, value: Value) !void {
    if (self.bindings.getPtr(key)) |val_ptr| {
        val_ptr.* = value;
        return;
    }

    if (self.parent) |parent| {
        return try parent.set(key, value);
    }

    log.err("{s} is not bound\n", .{key});
    return error.NotDefined;
}

pub fn get(self: *Environment, key: []const u8) !Value {
    if (self.bindings.get(key)) |maybe_value| {
        if (maybe_value) |value| return value;
        log.err("{s} is not bound\n", .{key});
        return error.NotDefined;
    }
    if (self.parent) |parent| {
        return parent.get(key);
    }
    log.err("{s} is not bound\n", .{key});
    return error.NotDefined;
}

const print = std.debug.print;

const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;

pub fn debug(self: *Environment) void {
    if (self.bindings.unmanaged.entries.len == 0) {
        print("{s}empty{s}\n", .{ ansi.dim, ansi.reset });
    }
    self.dbg(0);
}

fn dbg(self: *Environment, depth: usize) void {
    var it = self.bindings.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.*) |v|
            print("[{d}] {s} = {f}\n", .{ depth, entry.key_ptr.*, v })
        else
            print("[{d}] {s} = {s}free{s}\n", .{ depth, entry.key_ptr.*, ansi.dim, ansi.reset });
    }
    if (self.parent) |parent| {
        parent.dbg(depth + 1);
    }
}

test "bind, get, and get not bound" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();

    const x = Value.Number.init(123);
    try env.bind("x", x);

    try expect((try env.get("x")).equal(x));
    try expectError(error.NotDefined, env.get("y"));
}

test "shadowing prefers nearest scope" {
    const parent = try Environment.init(testing.allocator, null);
    try parent.bind("x", Value.Number.init(1));

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll();
    try child.bind("x", Value.Number.init(2));

    try expect((try child.get("x")).equal(Value.Number.init(2)));
    try expect((try parent.get("x")).equal(Value.Number.init(1)));
}

test "rebind in same scope errors" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();

    try env.bind("x", Value.Number.init(1));
    try expectError(error.AlreadyDefined, env.bind("x", Value.Number.init(2)));
}

test "set errors when name not declared" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();
    try expectError(error.NotDefined, env.set("x", Value.Number.init(1)));
}

test "set updates nearest declared in ancestor" {
    const parent = try Environment.init(testing.allocator, null);
    try parent.bind("x", Value.Number.init(1));

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll();

    try child.set("x", Value.Number.init(3));
    try expect((try parent.get("x")).equal(Value.Number.init(3)));
}

test "set fills previously-declared free slot" {
    const parent = try Environment.init(testing.allocator, null);
    try parent.bind("x", null);

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll();

    try child.set("x", Value.Number.init(7));
    try expect((try parent.get("x")).equal(Value.Number.init(7)));
}

test "deinitAll cleans whole chain" {
    const root = try Environment.init(testing.allocator, null);
    try root.bind("a", Value.Number.init(1));
    const mid = try Environment.init(testing.allocator, root);
    try mid.bind("b", Value.Number.init(2));
    const leaf = try Environment.init(testing.allocator, mid);
    try leaf.bind("c", Value.Number.init(3));

    leaf.deinitAll();
}
