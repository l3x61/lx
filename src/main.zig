const std = @import("std");
const Level = std.log.Level;
const Io = std.Io;

const fatal = std.process.fatal;

const Runtime = @import("Runtime.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &stdout_buf);
    const out = &stdout_writer.interface;
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(io, &stderr_buf);
    const err = &stderr_writer.interface;

    const file: []const u8 = if (argv.len > 1) argv[1] else "-";
    const source = try readSource(gpa, io, file);
    defer gpa.free(source);
    const name = if (std.mem.eql(u8, file, "-")) "<stdin>" else file;
    try runSource(gpa, io, name, source, out, err);
}

fn readSource(gpa: std.mem.Allocator, io: Io, file: []const u8) ![]u8 {
    if (std.mem.eql(u8, file, "-")) return readStdin(gpa);
    return Io.Dir.cwd().readFileAlloc(io, file, gpa, .limited(16 * 1024 * 1024)) catch |read_err|
        fatal("loading source {s} failed with {t}", .{ file, read_err });
}

fn readStdin(gpa: std.mem.Allocator) ![]u8 {
    var collected: std.ArrayList(u8) = .empty;
    errdefer collected.deinit(gpa);
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(std.posix.STDIN_FILENO, &chunk) catch |err|
            fatal("reading stdin failed with {t}", .{err});
        if (n == 0) break;
        try collected.appendSlice(gpa, chunk[0..n]);
    }
    return try collected.toOwnedSlice(gpa);
}

fn wrapTerminal(writer: *Io.Writer) Io.Terminal {
    return .{ .writer = writer, .mode = .escape_codes };
}

fn runSource(
    gpa: std.mem.Allocator,
    io: Io,
    name: []const u8,
    source: []const u8,
    out: *Io.Writer,
    err: *Io.Writer,
) !void {
    var runtime = try Runtime.init(gpa, io);
    defer runtime.deinit();

    const value = runtime.evaluateSourceNamed(name, source) catch |eval_err| switch (eval_err) {
        error.SyntaxError => {
            if (runtime.last_parse_error) |diagnostic| {
                diagnostic.write(wrapTerminal(err)) catch {};
                err.flush() catch {};
                std.process.exit(1);
            }
            fatal("{t}", .{eval_err});
        },
        else => fatal("{t}", .{eval_err}),
    };

    switch (value) {
        .unit => {},
        else => {
            value.write(out) catch {};
            out.writeByte('\n') catch {};
            out.flush() catch {};
        },
    }
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
}
