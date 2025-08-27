const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const eql = std.mem.eql;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const Interpreter = @import("Interpreter.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const readLine = @import("readline.zig").readline;
const Value = @import("value.zig").Value;

const Line = std.ArrayList([]u8);
const Repl = @This();

allocator: Allocator,
lines: Line,
env: *Environment,

pub fn init(allocator: Allocator) !Repl {
    return Repl{
        .allocator = allocator,
        .lines = Line.init(allocator),
        .env = try initEnvironment(allocator),
    };
}

fn initEnvironment(allocator: Allocator) !*Environment {
    const builtin_exit = @import("builtin/exit.zig");
    const builtin_env = @import("builtin/env.zig");
    const builtin_add = @import("builtin/add.zig");
    const builtin_sub = @import("builtin/sub.zig");
    const builtin_mul = @import("builtin/mul.zig");
    const builtin_div = @import("builtin/div.zig");

    var env = try Environment.init(allocator, null);

    try env.define(allocator, builtin_exit.name, Value.Builtin.init(builtin_exit.name, builtin_exit.function, null));
    try env.define(allocator, builtin_env.name, Value.Builtin.init(builtin_env.name, builtin_env.function, null));
    try env.define(allocator, builtin_add.name, Value.Builtin.init(builtin_add.name, builtin_add.function, null));
    try env.define(allocator, builtin_sub.name, Value.Builtin.init(builtin_sub.name, builtin_sub.function, null));
    try env.define(allocator, builtin_mul.name, Value.Builtin.init(builtin_mul.name, builtin_mul.function, null));
    try env.define(allocator, builtin_div.name, Value.Builtin.init(builtin_div.name, builtin_div.function, null));

    return env;
}

pub fn deinit(self: *Repl) void {
    for (self.lines.items) |line| {
        self.allocator.free(line);
    }
    self.lines.deinit();
}

pub fn run(self: *Repl) !void {
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();
    const prompt = ansi.cyan ++ "> " ++ ansi.reset;

    var int = try Interpreter.init(self.allocator, self.env);
    defer int.deinit();

    while (true) {
        const line = try readLine(self.allocator, prompt);
        try self.lines.append(line);

        var parser = try Parser.init(self.allocator, line);
        const ast = parser.parse() catch continue;

        //try stdout.print("{s}{s}{s}\n", .{ ansi.dimmed, ast, ansi.reset });

        const result = int.evaluate(ast) catch |err| {
            switch (err) {
                error.NormalExit => return,
                else => try stderr.print("{s}{s}{s}\n", .{ ansi.red, @errorName(err), ansi.reset }),
            }
            continue;
        };

        try stdout.print("{s}{s}{s}\n", .{ ansi.green, result, ansi.reset });
    }
}
