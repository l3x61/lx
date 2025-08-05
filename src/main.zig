const std = @import("std");
const builtin = @import("builtin");

const Repl = @import("Repl.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const allocator = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

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
