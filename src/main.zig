const std = @import("std");
const Level = std.log.Level;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const DebugAllocator = std.heap.DebugAllocator;

const fs = std.fs;

const log = std.log.scoped(.main);

const maxInt = std.math.maxInt;

const exit = std.process.exit;

const ansi = @import("ansi.zig");
const Repl = @import("Repl.zig");
const runScript = @import("runScript.zig").runScript;

pub const std_options = std.Options{
    .log_level = Level.debug,
    .logFn = logFn,
};

pub fn main() !void {
    var da: DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const gpa = da.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.next();
    const file_arg = args.next();

    // script mode
    if (file_arg) |file| {
        const script = std.fs.cwd().readFileAlloc(gpa, file, maxInt(u32)) catch |err| {
            log.err("reading {s} failed with {t}\n", .{ file, err });
            exit(1);
        };
        defer gpa.free(script);

        runScript(gpa, script) catch exit(1);
        return;
    }

    // interactive mode
    var repl = try Repl.init(gpa);
    defer repl.deinit();
    try repl.run();
    return;
}

fn logFn(
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
