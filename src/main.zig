const std = @import("std");
const Level = std.log.Level;
const builtin = @import("builtin");

const LoggingAllocator = @import("LoggingAllocator.zig");
const Repl = @import("Repl.zig");

pub const std_options = std.Options{
    .log_level = Level.info,
    .logFn = @import("util.zig").logFn,
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
