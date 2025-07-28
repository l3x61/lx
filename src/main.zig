const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello World!\n", .{});
}

test "all" {
    _ = @import("Lexer.zig");
}
