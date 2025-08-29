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

    pub fn deinit(self: *Object, ator: Allocator) void {
        switch (self.*) {
            .value => |*value| value.deinit(ator),
            .node => |node| node.deinit(ator),
            .env => |env| env.deinitSelf(ator),
        }
    }
};
