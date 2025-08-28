const std = @import("std");
const Level = std.log.Level;
const time = std.time;
const ns_per_us = time.ns_per_us;
const ns_per_ms = time.ns_per_ms;
const ns_per_s = time.ns_per_s;

const ansi = @import("ansi.zig");

pub fn formatElapsedTime(buffer: []u8, ns: u64) ![]const u8 {
    return switch (ns) {
        0...ns_per_us - 1 => try std.fmt.bufPrint(buffer, "{}ns", .{ns}),

        ns_per_us...ns_per_ms - 1 => block: {
            const us = @as(f64, @floatFromInt(ns)) / std.time.ns_per_us;
            break :block std.fmt.bufPrint(buffer, "{d:.2}μs", .{us});
        },

        ns_per_ms...ns_per_s - 1 => block: {
            const ms = @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
            break :block try std.fmt.bufPrint(buffer, "{d:.3}ms", .{ms});
        },

        else => block: {
            const s = @as(f64, @floatFromInt(ns)) / std.time.ns_per_s;
            break :block std.fmt.bufPrint(buffer, "{d:.6}s", .{s});
        },
    };
}

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

pub fn emptyLogFn(
    comptime _: Level,
    comptime _: @Type(.enum_literal),
    comptime _: []const u8,
    _: anytype,
) void {}
