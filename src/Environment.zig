const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringArrayHashMapUnmanaged;

const Value = @import("value.zig").Value;
const Environment = @This();

gpa: Allocator,
parent: ?*Environment,
bindings: HashMap(?Value),

pub fn init(gpa: Allocator, parent: ?*Environment) !*Environment {
    const self = try gpa.create(Environment);
    self.* = Environment{
        .gpa = gpa,
        .parent = parent,
        .bindings = .empty,
    };
    return self;
}

pub fn deinit(self: *Environment) void {
    var it = self.bindings.iterator();
    while (it.next()) |entry| {
        self.gpa.free(entry.key_ptr.*);
    }
    self.bindings.deinit(self.gpa);
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

    const entry = try self.bindings.getOrPut(self.gpa, new_key);
    if (entry.found_existing) {
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

    return error.NotDefined;
}

pub fn get(self: *Environment, key: []const u8) !Value {
    if (self.bindings.get(key)) |maybe_value| {
        if (maybe_value) |value| return value;
        return error.NotDefined;
    }
    if (self.parent) |parent| {
        return parent.get(key);
    }
    return error.NotDefined;
}

const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;

pub fn debug(self: *Environment) void {
    var buffer: [1024]u8 = undefined;
    const locked = std.debug.lockStderr(&buffer);
    defer std.debug.unlockStderr();
    const t = locked.terminal();

    if (self.bindings.entries.len == 0) {
        t.setColor(.dim) catch {};
        t.writer.writeAll("empty") catch {};
        t.setColor(.reset) catch {};
        t.writer.writeByte('\n') catch {};
    }
    self.dbg(t, 0);
}

fn dbg(self: *Environment, t: std.Io.Terminal, depth: usize) void {
    const w = t.writer;
    var it = self.bindings.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.*) |v| {
            w.print("[{d}] {s} = {f}\n", .{ depth, entry.key_ptr.*, v }) catch {};
        } else {
            w.print("[{d}] {s} = ", .{ depth, entry.key_ptr.* }) catch {};
            t.setColor(.dim) catch {};
            w.writeAll("free") catch {};
            t.setColor(.reset) catch {};
            w.writeByte('\n') catch {};
        }
    }
    if (self.parent) |parent| {
        parent.dbg(t, depth + 1);
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
