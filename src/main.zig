const std = @import("std");
const builtin = @import("builtin");

const Repl = @import("Repl.zig");
const LoggingAllocator = @import("LoggingAllocator.zig");

pub const std_options = std.Options{
    .log_level = .debug,
    .logFn = @import("logFn.zig").logFn,
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    var logging_allocator = LoggingAllocator.init(debug_allocator.allocator());
    const allocator = logging_allocator.allocator();
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
