const std = @import("std");
const Level = std.log.Level;

const ansi = @import("ansi.zig");



pub fn logFn(
    comptime message_level: Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const color = comptime switch (message_level) {
        .err => ansi.red,
        .warn => ansi.yellow,
        .info => ansi.green,
        .debug => ansi.dimmed,
    };
    const scope_name = if (scope == .default) "" else @tagName(scope) ++ ": ";
    var buffer: [256]u8 = undefined;
    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();
    nosuspend stderr.print(color ++ scope_name ++ ansi.dimmed ++ format ++ ansi.reset, args) catch return;
}
