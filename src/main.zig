const std = @import("std");
const Level = std.log.Level;
const DebugAllocator = std.heap.DebugAllocator;
const builtin = @import("builtin");

const LoggingAllocator = @import("LoggingAllocator.zig");
const Repl = @import("Repl.zig");

pub const std_options = std.Options{
    .log_level = Level.debug,
    .logFn = @import("util.zig").logFn,
};

pub fn main() !void {
    var da: DebugAllocator(.{}) = .init;
    defer _ = da.deinit();

    //var la = LoggingAllocator.init(da.allocator());
    const ator = da.allocator();

    var repl = try Repl.init(ator);
    defer repl.deinit();

    try repl.run();
}

test "all" {
    _ = @import("Lexer.zig");
    _ = @import("Parser.zig");
    _ = @import("Environment.zig");
    _ = @import("Interpreter.zig");
    _ = @import("String.zig");
}
