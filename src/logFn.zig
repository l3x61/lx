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
    };
    const scope_name = if (scope == .default) "" else @tagName(scope) ++ ": ";

    const stderr = std.io.getStdErr().writer();
    var buffered_writer = std.io.bufferedWriter(stderr);
    const writer = buffered_writer.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level ++ scope_name ++ ansi.dimmed ++ format ++ ansi.reset, args) catch unreachable;
        buffered_writer.flush() catch unreachable;
    }
}
