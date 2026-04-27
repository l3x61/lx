const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringArrayHashMapUnmanaged;

const Value = @import("value.zig").Value;
const Environment = @This();

gpa: Allocator,
parent: ?*Environment,
bindings: HashMap(?Value),

pub const Snapshot = struct {
    count: usize,
    values: []?Value,

    pub fn deinit(self: Snapshot, gpa: Allocator) void {
        gpa.free(self.values);
    }
};

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
        return error.UninitializedBinding;
    }
    if (self.parent) |parent| {
        return parent.get(key);
    }
    return error.NotDefined;
}

pub fn snapshot(self: *Environment) !Snapshot {
    return .{
        .count = self.bindings.count(),
        .values = try self.gpa.dupe(?Value, self.bindings.values()),
    };
}

pub fn restore(self: *Environment, snapshot_value: Snapshot) void {
    const values = self.bindings.values();
    @memcpy(values[0..snapshot_value.count], snapshot_value.values);

    while (self.bindings.count() > snapshot_value.count) {
        const key = self.bindings.keys()[snapshot_value.count];
        self.bindings.orderedRemoveAt(snapshot_value.count);
        self.gpa.free(key);
    }
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

    const x = Value.Integer.init(123);
    try env.bind("x", x);

    try expect((try env.get("x")).equal(x));
    try expectError(error.NotDefined, env.get("y"));
}

test "shadowing prefers nearest scope" {
    const parent = try Environment.init(testing.allocator, null);
    try parent.bind("x", Value.Integer.init(1));

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll();
    try child.bind("x", Value.Integer.init(2));

    try expect((try child.get("x")).equal(Value.Integer.init(2)));
    try expect((try parent.get("x")).equal(Value.Integer.init(1)));
}

test "rebind in same scope errors" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();

    try env.bind("x", Value.Integer.init(1));
    try expectError(error.AlreadyDefined, env.bind("x", Value.Integer.init(2)));
}

test "set errors when name not declared" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();
    try expectError(error.NotDefined, env.set("x", Value.Integer.init(1)));
}

test "set updates nearest declared in ancestor" {
    const parent = try Environment.init(testing.allocator, null);
    try parent.bind("x", Value.Integer.init(1));

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll();

    try child.set("x", Value.Integer.init(3));
    try expect((try parent.get("x")).equal(Value.Integer.init(3)));
}

test "set fills previously-declared free slot" {
    const parent = try Environment.init(testing.allocator, null);
    try parent.bind("x", null);

    const child = try Environment.init(testing.allocator, parent);
    defer child.deinitAll();

    try child.set("x", Value.Integer.init(7));
    try expect((try parent.get("x")).equal(Value.Integer.init(7)));
}

test "snapshot restore removes new bindings and resets existing values" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();

    try env.bind("x", Value.Integer.init(1));
    const mark = try env.snapshot();
    defer mark.deinit(testing.allocator);

    try env.set("x", Value.Integer.init(2));
    try env.bind("y", Value.Integer.init(3));

    env.restore(mark);

    try expect((try env.get("x")).equal(Value.Integer.init(1)));
    try expectError(error.NotDefined, env.get("y"));
}

test "snapshot restore preserves preallocated cells" {
    const env = try Environment.init(testing.allocator, null);
    defer env.deinitAll();

    try env.bind("x", null);
    const mark = try env.snapshot();
    defer mark.deinit(testing.allocator);

    try env.set("x", Value.Integer.init(2));
    env.restore(mark);

    try expectError(error.UninitializedBinding, env.get("x"));
}

test "deinitAll cleans whole chain" {
    const root = try Environment.init(testing.allocator, null);
    try root.bind("a", Value.Integer.init(1));
    const mid = try Environment.init(testing.allocator, root);
    try mid.bind("b", Value.Integer.init(2));
    const leaf = try Environment.init(testing.allocator, mid);
    try leaf.bind("c", Value.Integer.init(3));

    leaf.deinitAll();
}
