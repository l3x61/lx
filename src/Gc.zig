const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const ArrayList = std.ArrayList;
const Env = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;
const String = Value.String;
const Native = Value.Native;
const Closure = Value.Closure;

const log = std.log.scoped(.gc);

const Gc = @This();

const GcObject = struct {
    marked: bool = false,
    object: union(Tag) {
        pub const Tag = enum {
            env,
            node,
            string,
            native,
            closure,
        };

        env: *Env,
        node: *Node,
        string: *String,
        native: *Native,
        closure: *Closure,
    },
};

arena: ArenaAllocator,
objects: ArrayList(GcObject),

pub fn init(gpa: Allocator) !Gc {
    return .{
        .arena = ArenaAllocator.init(gpa),
        .objects = .empty,
    };
}

pub fn allocator(self: *Gc) Allocator {
    return self.arena.allocator();
}

pub fn deinit(self: *Gc) void {
    const gpa = self.allocator();
    for (self.objects.items) |*object| {
        switch (object.object) {
            .env => |env| env.deinit(),
            .node => |node| node.deinit(gpa),
            .string => |string| string.deinit(gpa),
            .native => |native| native.deinit(gpa),
            .closure => |closure| closure.deinit(gpa),
        }
    }
    self.arena.deinit();
}

pub fn track(self: *Gc, object: anytype) !void {
    const gpa = self.allocator();
    switch (@TypeOf(object)) {
        *Env => try self.objects.append(gpa, .{ .object = .{ .env = object } }),
        *Node => try self.objects.append(gpa, .{ .object = .{ .node = object } }),
        Value => switch (object) {
            .string => |string| try self.objects.append(gpa, .{ .object = .{ .string = string } }),
            .native => |native| try self.objects.append(gpa, .{ .object = .{ .native = native } }),
            .closure => |closure| try self.objects.append(gpa, .{ .object = .{ .closure = closure } }),
            else => log.warn("ignored: tracking a non-object: {s}\n", .{@typeName(@TypeOf(object))}),
        },
        else => log.warn("ignored: tracking a non-object: {s}\n", .{@typeName(@TypeOf(object))}),
    }
}

const testing = std.testing;

test "track environment" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const gpa = gc.allocator();
    const env = try Env.init(gpa, null);
    try gc.track(env);

    try testing.expectEqual(@as(usize, 1), gc.objects.items.len);
}

test "track node" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const gpa = gc.allocator();
    const token = Token.init(.number, "1", "1");
    const node = try Node.Primary.init(gpa, token);
    try gc.track(node);

    try testing.expectEqual(@as(usize, 1), gc.objects.items.len);
}

test "track string value" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const gpa = gc.allocator();
    const value = try String.init(gpa, "hello");
    try gc.track(value);

    try testing.expectEqual(@as(usize, 1), gc.objects.items.len);
}

fn nativeFn(_: Value, _: *Env, _: ?*Env) anyerror!Value {
    return Value.init();
}

test "track native value" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const gpa = gc.allocator();
    const value = try Native.init(gpa, "dummy", nativeFn, null);
    try gc.track(value);

    try testing.expectEqual(@as(usize, 1), gc.objects.items.len);
}

test "track closure value" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const gpa = gc.allocator();
    const env = try Env.init(testing.allocator, null);
    defer env.deinit();

    const body_token = Token.init(.number, "1", "1");
    const body = try Node.Primary.init(gpa, body_token);
    defer body.deinit(gpa);

    const param = Token.init(.identifier, "x", "x");
    const func = Node.Function{ .parameter = param, .body = body };
    const value = try Closure.init(gpa, func, env);
    try gc.track(value);

    try testing.expectEqual(@as(usize, 1), gc.objects.items.len);
}

test "non-object tracking is ignored" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    try gc.track(Value.Number.init(1));

    var non_gc_value: usize = 123;
    try gc.track(&non_gc_value);

    try testing.expectEqual(@as(usize, 0), gc.objects.items.len);
}
