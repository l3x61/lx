const std = @import("std");
const Level = std.log.Level;
const DebugAllocator = std.heap.DebugAllocator;

const ansi = @import("ansi.zig");
const Repl = @import("Repl.zig");

pub const std_options = std.Options{
    .log_level = Level.debug,
    .logFn = logFn,
};

pub fn main() !void {
    var da: DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const gpa = da.allocator();

    var repl = try Repl.init(gpa);
    defer repl.deinit();

    try repl.run();
}

pub fn logFn(
    comptime level: Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const color = comptime switch (level) {
        .err => ansi.red,
        .warn => ansi.yellow,
        .info => ansi.green,
        .debug => ansi.dim,
    };
    const name = if (scope == .default) "" else @tagName(scope) ++ ": ";
    var buffer: [256]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    nosuspend stderr.print(color ++ name ++ ansi.dim ++ format ++ ansi.reset, args) catch return;
}

test "all" {
    _ = @import("Lexer.zig");
    _ = @import("Parser.zig");
    _ = @import("Environment.zig");
    _ = @import("evaluate.zig");
}
