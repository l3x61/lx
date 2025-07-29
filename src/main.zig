const std = @import("std");
const allocator = std.heap.c_allocator;
const print = std.debug.print;
const eql = std.mem.eql;

const ansi = @import("ansi.zig");
const Interpreter = @import("Interpreter.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const readLine = @import("readline.zig").readline;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    while (true) {
        const line = try readLine(allocator, ansi.cyan ++ "> " ++ ansi.reset);
        defer allocator.free(line);

        var parser = try Parser.init(allocator, line);
        const ast = parser.parse() catch |err| {
            print(ansi.red ++ "parser error:" ++ ansi.reset ++ " {s}\n", .{@errorName(err)});
            continue;
        };
        defer ast.deinit(allocator);
        //try ast.debug(allocator);

        var int = try Interpreter.init(allocator);
        defer int.deinit();

        const result = int.evaluate(ast) catch |err| {
            print(ansi.red ++ "runtime error:" ++ ansi.reset ++ " {s}\n", .{@errorName(err)});
            continue;
        };
        try stdout.print("{s}\n", .{result});
    }
}

test "all" {
    _ = @import("Lexer.zig");
    _ = @import("Parser.zig");
    _ = @import("Environment.zig");
    _ = @import("Interpreter.zig");
}
