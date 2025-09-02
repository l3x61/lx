const std = @import("std");
const Allocator = std.mem.Allocator;
const FormatOptions = std.fmt.FormatOptions;

const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Value = @import("value.zig").Value;

pub const Tag = enum {
    env,
    node,
    value,

    pub fn format(self: Tag, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Object = union(Tag) {
    env: *Environment,
    node: *Node,
    value: Value,

    // TODO: actually collect garbage
    pub fn deinit(self: *Object, gpa: Allocator) void {
        switch (self.*) {
            .value => |*value| value.deinit(gpa),
            .node => |node| node.deinit(gpa),
            .env => |env| env.deinitSelf(),
        }
    }
};
