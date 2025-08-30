const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const max_path_bytes = std.fs.max_path_bytes;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const formatElapsedTime = @import("util.zig").formatElapsedTime;
const Interpreter = @import("Interpreter.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const readLine = @import("readline.zig").readLine;
const Value = @import("value.zig").Value;
const String = @import("String.zig");

const log = std.log.scoped(.repl);
const Lines = std.ArrayList(String);
const Repl = @This();

ator: Allocator,
lines: Lines,
env: *Environment,

var stdout_buffer: [max_path_bytes]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var stdin_buffer: [max_path_bytes]u8 = undefined;
var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
const stdin = &stdin_reader.interface;

pub fn init(ator: Allocator) !Repl {
    return Repl{
        .ator = ator,
        .lines = .empty,
        .env = try initEnvironment(ator),
    };
}

fn initEnvironment(ator: Allocator) !*Environment {
    const builtin_exit = @import("builtin/exit.zig");
    const builtin_env = @import("builtin/env.zig");

    var env = try Environment.init(ator, null);
    try env.define(ator, builtin_exit.name, Value.Builtin.init(builtin_exit.name, builtin_exit.function, null));
    try env.define(ator, builtin_env.name, Value.Builtin.init(builtin_env.name, builtin_env.function, null));

    return env;
}

pub fn deinit(self: *Repl) void {
    for (self.lines.items) |*line| {
        line.deinit(self.ator);
    }
    self.lines.deinit(self.ator);
}

pub fn run(self: *Repl) !void {
    const ator = self.ator;
    const env = self.env;

    const prompt = ansi.cyan ++ "> " ++ ansi.reset;

    var interp = try Interpreter.init(ator, env);
    defer interp.deinit();

    while (true) {
        const line = readLine(ator, prompt, stdout) catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };
        try self.lines.append(ator, line);

        var timer = try Timer.start();
        var parser = try Parser.init(ator, line.getSlice());
        const ast = parser.parse() catch continue;
        defer ast.deinit(ator);
        const parse_done = timer.lap();

        log.debug("{f}\n", .{ast});

        _ = timer.lap();
        const result = interp.evaluate(ast) catch |err| {
            log.warn("{s}\n", .{@errorName(err)});
            continue;
        };
        const eval_done = timer.read();

        log.info("parsing    {s}\n", .{try formatElapsedTime(&stdout_buffer, parse_done)});
        log.info("evaluating {s}\n", .{try formatElapsedTime(&stdout_buffer, eval_done)});

        try stdout.print("{f}\n", .{result});
        try stdout.flush();
    }
}
