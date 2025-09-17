const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const ArrayList = std.ArrayList;
const Env = @import("Environment.zig");
const Node = @import("node.zig").Node;
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

pub fn deinit(self: *Gc) void {
    const gpa = self.arena.allocator();
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
    const gpa = self.arena.allocator();
    try switch (@TypeOf(object)) {
        *Env => self.objects.append(gpa, .{ .object = .{ .env = object } }),
        *Node => self.objects.append(gpa, .{ .object = .{ .node = object } }),
        Value => switch (object) {
            .string => |string| self.objects.append(gpa, .{ .object = .{ .string = string } }),
            .native => |native| self.objects.append(gpa, .{ .object = .{ .native = native } }),
            .closure => |closure| self.objects.append(gpa, .{ .object = .{ .closure = closure } }),
            else => log.warn("ignored: tracking a non-object: {s}\n", .{@typeName(@TypeOf(object))}),
        },
        else => log.warn("ignored: tracking a non-object: {s}\n", .{@typeName(@TypeOf(object))}),
    };
}
