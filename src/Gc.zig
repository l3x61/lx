const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Value = @import("value.zig").Value;

const Gc = @This();

const Tracked = union(enum) {
    env: *Environment,
    node: *Node,
    bytes: []u8,
    string: *Value.String,
    list: *Value.List,
    tuple: *Value.Tuple,
    map: *Value.Map,
    native: *Value.Native,
    closure: *Value.Closure,
};

gpa: Allocator,
io: Io,
objects: std.ArrayList(Tracked),

pub fn init(gpa: Allocator, io: Io) !Gc {
    return .{
        .gpa = gpa,
        .io = io,
        .objects = .empty,
    };
}

pub fn deinit(self: *Gc) void {
    for (self.objects.items) |object| {
        switch (object) {
            .env => |env| env.deinit(),
            .node => |node| node.deinit(self.gpa),
            .bytes => |bytes| self.gpa.free(bytes),
            .string => |string| string.deinit(self.gpa),
            .list => |list| list.deinit(self.gpa),
            .tuple => |tuple| tuple.deinit(self.gpa),
            .map => |map| map.deinit(self.gpa),
            .native => |native| native.deinit(self.gpa),
            .closure => |closure| self.gpa.destroy(closure),
        }
    }
    self.objects.deinit(self.gpa);
}

pub fn allocator(self: *Gc) Allocator {
    return self.gpa;
}

pub fn nativeContext(self: *Gc) Value.NativeContext {
    return .{
        .gpa = self.gpa,
        .io = self.io,
        .tracker = self,
        .trackFn = trackNativeValue,
    };
}

pub fn track(self: *Gc, object: anytype) !void {
    const tracked: ?Tracked = switch (@TypeOf(object)) {
        *Environment => .{ .env = object },
        *Node => .{ .node = object },
        []u8 => .{ .bytes = object },
        Value => switch (object) {
            .string => |string| .{ .string = string },
            .list => |list| .{ .list = list },
            .tuple => |tuple| .{ .tuple = tuple },
            .map => |map| .{ .map = map },
            .native => |native| .{ .native = native },
            .closure => |closure| .{ .closure = closure },
            else => null,
        },
        else => null,
    };

    if (tracked) |entry| {
        try self.objects.append(self.gpa, entry);
    }
}

fn trackNativeValue(tracker: *anyopaque, value: Value) anyerror!void {
    const self: *Gc = @ptrCast(@alignCast(tracker));
    try self.track(value);
}

const testing = std.testing;

test "tracks runtime objects" {
    var gc = try Gc.init(testing.allocator, testing.io);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    try gc.track(env);

    const string = try Value.String.init(testing.allocator, "hello");
    try gc.track(string);

    try testing.expectEqual(@as(usize, 2), gc.objects.items.len);
}
