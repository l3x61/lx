const std = @import("std");
const Allocator = std.mem.Allocator;
const FormatOptions = std.fmt.FormatOptions;

const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Value = @import("value.zig").Value;

pub const Tag = enum {
    value,
    node,
    env,

    pub fn format(self: Tag, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Object = union(Tag) {
    value: Value,
    node: *Node,
    env: *Environment,

    pub fn deinit(self: *Object, allocator: Allocator) void {
        switch (self.*) {
            .value => |*value| value.deinit(allocator),
            .node => |node| node.deinit(allocator),
            .env => |env| env.deinitSelf(allocator),
        }
    }
};
