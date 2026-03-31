const std = @import("std");
const Level = std.log.Level;
const Allocator = std.mem.Allocator;
const DebugAllocator = std.heap.DebugAllocator;

const log = std.log.scoped(.main);

const exit = std.process.exit;

const ansi = @import("ansi.zig");
const Repl = @import("Repl.zig");

pub const std_options = std.Options{
    .logFn = struct {
        fn logFn(
            comptime level: Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const color = comptime switch (level) {
                .err => ansi.red,
                .warn => ansi.red,
                .info => ansi.dim,
                .debug => ansi.dim,
            };
            const name = if (scope == .default) "" else @tagName(scope) ++ ": ";
            var buffer: [256]u8 = undefined;
            const stderr = std.debug.lockStderrWriter(&buffer);
            defer std.debug.unlockStderrWriter();
            nosuspend stderr.print(color ++ name ++ ansi.dim ++ format ++ ansi.reset, args) catch return;
        }
    }.logFn,
};

pub fn main() !void {
    var da: DebugAllocator(.{}) = .init;
    defer _ = {
        if (da.deinit() == .leak) log.err("memory leaked\n", .{});
    };
    const gpa = da.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.next();
    const file_arg = args.next();

    if (file_arg) |file| {
        const source = std.fs.cwd().readFileAlloc(gpa, file, 16 * 1024 * 1024) catch |err| {
            log.err("loading source {s} failed with {t}\n", .{ file, err });
            return error.LoadScript;
        };
        defer gpa.free(source);

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        Repl.dumpTokens(&stdout_writer.interface, source) catch exit(1);
        stdout_writer.interface.writeAll("\n") catch {};
        stdout_writer.interface.flush() catch {};
        return;
    }

    var repl = try Repl.init(gpa);
    defer repl.deinit();
    try repl.run();
    return;
}

test "all" {
    _ = @import("Token.zig");
    _ = @import("Lexer.zig");
    _ = @import("readline.zig");
    _ = @import("Repl.zig");
}
