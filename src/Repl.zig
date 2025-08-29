const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const formatElapsedTime = @import("util.zig").formatElapsedTime;
const Interpreter = @import("Interpreter.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const readLine = @import("readline.zig").readline;
const Value = @import("value.zig").Value;

const log = std.log.scoped(.repl);
const Lines = std.array_list.AlignedManaged([]u8, null);
const Repl = @This();

ator: Allocator,
lines: Lines,
env: *Environment,

pub fn init(ator: Allocator) !Repl {
    return Repl{
        .ator = ator,
        .lines = Lines.init(ator),
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
    for (self.lines.items) |line| {
        self.ator.free(line);
    }
    self.lines.deinit();
}

pub fn run(self: *Repl) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    const stdout = &stdout_writer.interface;

    try stdout.flush();

    var interp = try Interpreter.init(self.ator, self.env);
    defer interp.deinit();

    while (true) {
        const line = try readLine(self.ator, ansi.cyan ++ "> " ++ ansi.reset);
        try self.lines.append(line);

        var timer = try Timer.start();
        var parser = try Parser.init(self.ator, line);
        const ast = parser.parse() catch continue;
        const parse_done = timer.lap();

        log.debug("{f}\n", .{ast});

        _ = timer.lap();
        const result = interp.evaluate(ast) catch |err| {
            switch (err) {
                error.NormalExit => return,
                else => log.warn("{s}\n", .{@errorName(err)}),
            }
            continue;
        };
        const eval_done = timer.read();

        log.info("parsing    {s}\n", .{try formatElapsedTime(&buffer, parse_done)});
        log.info("evaluating {s}\n", .{try formatElapsedTime(&buffer, eval_done)});

        try stdout.print("{f}\n", .{result});
        try stdout.flush();
    }
}
