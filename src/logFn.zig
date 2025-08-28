const std = @import("std");
const Level = std.log.Level;

const ansi = @import("ansi.zig");

pub fn logFn(
    comptime message_level: Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level = comptime switch (message_level) {
        .err => ansi.red,
        .warn => ansi.yellow,
        .info => ansi.cyan,
        .debug => ansi.dimmed,
        // .err => ansi.red ++ "error" ++ ansi.reset,
        // .warn => ansi.yellow ++ "warning" ++ ansi.reset,
        // .info => ansi.cyan ++ "info" ++ ansi.reset,
        // .debug => ansi.dimmed ++ "debug" ++ ansi.reset,
    };
    const scope_name = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    const stderr = std.io.getStdErr().writer();
    var buffered_writer = std.io.bufferedWriter(stderr);
    const writer = buffered_writer.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level ++ scope_name ++ format ++ ansi.reset ++ "\n", args) catch return;
        buffered_writer.flush() catch return;
    }
}
