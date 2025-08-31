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
const ReadLine = @import("ReadLine.zig");
const Value = @import("value.zig").Value;

const log = std.log.scoped(.repl);
const String = std.ArrayList(u8);
const Lines = std.ArrayList(String);
const Repl = @This();

gpa: Allocator,
env: *Environment,
rl: ReadLine,

var stdout_buffer: [max_path_bytes]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var stdin_buffer: [max_path_bytes]u8 = undefined;
var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
const stdin = &stdin_reader.interface;

fn initEnv(gpa: Allocator) !*Environment {
    const builtin_exit = @import("builtin/exit.zig");
    const builtin_env = @import("builtin/env.zig");

    var env = try Environment.init(gpa, null);
    try env.define(gpa, builtin_exit.name, Value.Builtin.init(builtin_exit.name, builtin_exit.function, null));
    try env.define(gpa, builtin_env.name, Value.Builtin.init(builtin_env.name, builtin_env.function, null));

    return env;
}

pub fn init(gpa: Allocator) !Repl {
    return Repl{
        .gpa = gpa,
        .env = try initEnv(gpa),
        .rl = ReadLine.init(gpa, stdout),
    };
}

pub fn deinit(self: *Repl) void {
    self.rl.deinit();
}

pub fn run(self: *Repl) !void {
    const gpa = self.gpa;
    const env = self.env;
    var rl = self.rl;

    const prompt = ansi.cyan ++ "> " ++ ansi.reset;

    var interp = try Interpreter.init(gpa, env);
    defer interp.deinit();

    while (true) {
        const line = rl.readLine(prompt) catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };

        var timer = try Timer.start();
        var parser = try Parser.init(gpa, line.items);
        const ast = parser.parse() catch continue;
        defer ast.deinit(gpa);
        const parse_done = timer.lap();

        //log.debug("{f}\n", .{ast});

        _ = timer.lap();
        const result = interp.evaluate(ast) catch |err| {
            log.err("{s}\n", .{@errorName(err)});
            continue;
        };
        const eval_done = timer.read();

        log.info("parsing    {s}\n", .{try formatElapsedTime(&stdout_buffer, parse_done)});
        log.info("evaluating {s}\n", .{try formatElapsedTime(&stdout_buffer, eval_done)});

        try stdout.print(ansi.bold ++ "{f}\n" ++ ansi.reset, .{result});
        try stdout.flush();
    }
}
