const std = @import("std");
const Level = std.log.Level;
const Io = std.Io;

const log = std.log.scoped(.main);
const fatal = std.process.fatal;

const term = @import("term.zig");
const Repl = @import("Repl.zig");
const Runtime = @import("Runtime.zig");

pub const std_options = std.Options{
    .logFn = struct {
        fn logFn(
            comptime level: Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            var buffer: [256]u8 = undefined;
            const locked = std.debug.lockStderr(&buffer);
            defer std.debug.unlockStderr();
            const t = locked.terminal();
            const color: std.Io.Terminal.Color = switch (level) {
                .err, .warn => .red,
                .info, .debug => .dim,
            };
            nosuspend {
                t.setColor(color) catch return;
                if (scope != .default) {
                    t.writer.writeAll(@tagName(scope)) catch return;
                    t.writer.writeAll(": ") catch return;
                }
                t.setColor(.dim) catch return;
                t.writer.print(format, args) catch return;
                t.setColor(.reset) catch return;
            }
        }
    }.logFn,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);

    var mode: Repl.AstMode = .off;
    var file_arg: ?[]const u8 = null;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "--ast-tree")) {
            mode = .tree;
            continue;
        }
        if (std.mem.eql(u8, arg, "--ast-off")) {
            mode = .off;
            continue;
        }
        file_arg = arg;
        break;
    }

    if (file_arg) |file| {
        const source = Io.Dir.cwd().readFileAlloc(io, file, gpa, .limited(16 * 1024 * 1024)) catch |err|
            fatal("loading source {s} failed with {t}", .{ file, err });
        defer gpa.free(source);

        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = Io.File.stdout().writer(io, &stdout_buffer);
        const out = &stdout_writer.interface;
        if (mode == .off) {
            var runtime = try Runtime.init(gpa, io);
            defer runtime.deinit();
            const value = runtime.evaluateSource(source) catch |err|
                fatal("{t}", .{err});
            switch (value) {
                .unit => {},
                else => {
                    value.write(out) catch {};
                    out.writeByte('\n') catch {};
                    out.flush() catch {};
                },
            }
        } else {
            Repl.render(term.wrap(out), gpa, source, mode) catch |err|
                fatal("{t}", .{err});
            out.writeByte('\n') catch {};
            out.flush() catch {};
        }
        return;
    }

    const repl = try Repl.init(gpa, io);
    defer repl.deinit();
    try repl.run();
}

test "all" {
    _ = @import("Token.zig");
    _ = @import("Lexer.zig");
    _ = @import("node.zig");
    _ = @import("Parser.zig");
    _ = @import("Environment.zig");
    _ = @import("value.zig");
    _ = @import("Gc.zig");
    _ = @import("builtins.zig");
    _ = @import("evaluate.zig");
    _ = @import("Runtime.zig");
    _ = @import("Script.zig");
    _ = @import("readline.zig");
    _ = @import("Repl.zig");
    _ = @import("term.zig");
}
