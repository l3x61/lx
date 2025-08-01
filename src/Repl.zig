const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const eql = std.mem.eql;

const ansi = @import("ansi.zig");
const Interpreter = @import("Interpreter.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const readLine = @import("readline.zig").readline;

const Repl = @This();

allocator: Allocator,

pub fn init(allocator: Allocator) Repl {
    return Repl{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Repl) void {
    _ = self;
}

pub fn run(self: *Repl) !void {
    const stdout = std.io.getStdOut().writer();
    const prompt = ansi.cyan ++ "> " ++ ansi.reset;
    while (true) {
        const line = try readLine(self.allocator, prompt);
        defer self.allocator.free(line);

        var parser = try Parser.init(self.allocator, line);
        const ast = parser.parse() catch continue;
        try stdout.print("{s}{s}{s}\n", .{ ansi.dimmed, ast, ansi.reset });
        defer ast.deinit(self.allocator);

        var int = try Interpreter.init(self.allocator);
        defer int.deinit();

        const result = int.evaluate(ast) catch continue;
        try stdout.print("{s}\n", .{result});
    }
}
