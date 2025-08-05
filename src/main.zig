const std = @import("std");
const allocator = std.heap.c_allocator;

const Repl = @import("Repl.zig");

pub fn main() !void {
    var repl = try Repl.init(allocator);
    defer repl.deinit();

    try repl.run();
}

test "all" {
    _ = @import("Lexer.zig");
    _ = @import("Parser.zig");
    _ = @import("Environment.zig");
    _ = @import("Interpreter.zig");
}
