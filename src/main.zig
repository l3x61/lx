const std = @import("std");
const allocator = std.heap.c_allocator;
const print = std.debug.print;
const eql = std.mem.eql;

const ansi = @import("ansi.zig");
const Lexer = @import("Lexer.zig");
const readLine = @import("readline.zig").readline;

pub fn main() !void {
    while (true) {
        const line = try readLine(allocator, ansi.cyan ++ "> " ++ ansi.reset);
        defer allocator.free(line);

        var lexer = try Lexer.init(line);
        var token = lexer.nextToken();
        while (token.tag != .eof) : (token = lexer.nextToken()) {
            if (token.tag == .symbol and eql(u8, token.lexeme, "exit")) return;
            print(ansi.dimmed ++ "{s}\n" ++ ansi.reset, .{token});
        }
    }
}

test "all" {
    _ = @import("Lexer.zig");
}
