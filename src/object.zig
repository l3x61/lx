const std = @import("std");
const Allocator = std.mem.Allocator;
const FormatOptions = std.fmt.FormatOptions;

const Environment = @import("Environment.zig");
const Value = @import("value.zig").Value;

pub const Tag = enum {
    value,
    env,

    pub fn format(self: Tag, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub const Object = union(Tag) {
    value: Value,
    env: *Environment,

    pub fn deinit(self: *Object, allocator: Allocator) void {
        switch (self.*) {
            .value => |*value| value.deinit(allocator),
            .env => |env| env.deinitSelf(allocator),
        }
    }
};
