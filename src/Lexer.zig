const std = @import("std");
const Utf8View = std.unicode.Utf8View;
const Utf8Iterator = std.unicode.Utf8Iterator;
const parseFloat = std.fmt.parseFloat;
const print = std.debug.print;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const hexEscape = std.ascii.hexEscape;

const ansi = @import("ansi.zig");
const Token = @import("Token.zig");

const Lexer = @This();

const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "let", .let },
    .{ "in", .in },
    .{ "if", .@"if" },
    .{ "then", .then },
    .{ "else", .@"else" },
    .{ "true", .true },
    .{ "false", .false },
});

source: []const u8,
iterator: Utf8Iterator,

pub fn init(source: []const u8) error{InvalidUtf8}!Lexer {
    var utf8_view = try Utf8View.init(source);
    return Lexer{ .source = source, .iterator = utf8_view.iterator() };
}

pub fn nextToken(self: *Lexer) Token {
    const source = self.source;
    const iterator = &self.iterator;

    const State = enum {
        start,
        comment,
        equal,
        number,
        string,
        identifier,
    };

    var start = iterator.i;
    var tag: Token.Tag = .eof;

    state: switch (State.start) {
        .start => switch (iterator.nextCodepoint() orelse break :state) {
            '\t', '\n', '\r', ' ' => {
                start = iterator.i;
                continue :state .start;
            },
            '#' => {
                tag = .comment;
                continue :state .comment;
            },
            '\\', 'λ' => {
                tag = .lambda;
                break :state;
            },
            '=' => {
                tag = .assign;
                continue :state .equal;
            },
            '.' => {
                tag = .dot;
                break :state;
            },
            '!' => {
                const previous = iterator.i;
                switch (iterator.nextCodepoint() orelse break :state) {
                    '=' => {
                        tag = .not_equal;
                    },
                    else => {
                        iterator.i = previous;
                        tag = .not;
                    },
                }
                break :state;
            },
            '(' => {
                tag = .lparen;
                break :state;
            },
            ')' => {
                tag = .rparen;
                break :state;
            },
            '+' => {
                const previous = iterator.i;
                switch (iterator.nextCodepoint() orelse break :state) {
                    '+' => {
                        tag = .concat;
                    },
                    else => {
                        iterator.i = previous;
                        tag = .plus;
                    },
                }
                break :state;
            },
            '-' => {
                tag = .minus;
                break :state;
            },
            '*' => {
                tag = .star;
                break :state;
            },
            '/' => {
                tag = .slash;
                break :state;
            },
            '0'...'9' => {
                tag = .number;
                continue :state .number;
            },
            '"' => {
                tag = .string;
                continue :state .string;
            },
            else => {
                tag = .identifier;
                continue :state .identifier;
            },
        },
        .comment => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '\n' => {
                    iterator.i = previous;
                    break :state;
                },
                else => continue :state .comment,
            }
            tag = .comment;
        },
        .equal => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '=' => {
                    tag = .equal;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },
        .string => {
            switch (iterator.nextCodepoint() orelse {
                tag = .string_open;
                break :state;
            }) {
                '"' => {
                    tag = .string;
                    break :state;
                },
                else => continue :state .string,
            }
            tag = .string;
        },
        .number => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '0'...'9' => continue :state .number,
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
            tag = .number;
        },
        .identifier => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '\t', '\n', '\r', ' ', '.', '+', '-', '*', '/', '"', '(', ')' => {
                    iterator.i = previous;
                    break :state;
                },
                else => continue :state .identifier,
            }
        },
    }

    const lexeme = source[start..iterator.i];

    if (keywords.get(lexeme)) |keyword| return Token.init(keyword, source, lexeme);
    return Token.init(tag, source, lexeme);
}

fn runTest(input: []const u8, tokens: []const Token) !void {
    var lexer = try Lexer.init(input);

    const escaped = hexEscape(input, .upper);
    for (0.., tokens) |i, expected| {
        const actual = lexer.nextToken();

        expect(expected.equal(actual)) catch |err| {
            print(ansi.red ++ "error: " ++ ansi.reset, .{});
            print("at token {d} of {d} in `{s}`\n", .{ i, tokens.len, escaped.data.bytes });
            print("expected: {f} `{s}`\n", .{ expected.tag, expected.lexeme });
            print("     got: {f} `{s}`\n\n", .{ actual.tag, actual.lexeme });
            return err;
        };
    }
}

test "empty" {
    const input = "";
    const tokens = [_]Token{
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "lone continuation byte" {
    const input = "\x80";
    try expectError(error.InvalidUtf8, runTest(input, &.{}));
}

test "truncated 2-byte sequence" {
    const input = "\xC2";
    try expectError(error.InvalidUtf8, runTest(input, &.{}));
}

test "identifier" {
    const input = "abc";
    const tokens = [_]Token{
        Token.init(.identifier, input, "abc"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "identifiers" {
    const input = "a b c";
    const tokens = [_]Token{
        Token.init(.identifier, input, "a"),
        Token.init(.identifier, input, "b"),
        Token.init(.identifier, input, "c"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "lambda with dot" {
    const input = "\\x.x";
    const tokens = [_]Token{
        Token.init(.lambda, input, "\\"),
        Token.init(.identifier, input, "x"),
        Token.init(.dot, input, "."),
        Token.init(.identifier, input, "x"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "lambda with unicode λ" {
    const input = "λx.x";
    const tokens = [_]Token{
        Token.init(.lambda, input, "λ"),
        Token.init(.identifier, input, "x"),
        Token.init(.dot, input, "."),
        Token.init(.identifier, input, "x"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "let in" {
    const input = "let id = λx.x in id 5";
    const tokens = [_]Token{
        Token.init(.let, input, "let"),
        Token.init(.identifier, input, "id"),
        Token.init(.assign, input, "="),
        Token.init(.lambda, input, "λ"),
        Token.init(.identifier, input, "x"),
        Token.init(.dot, input, "."),
        Token.init(.identifier, input, "x"),
        Token.init(.in, input, "in"),
        Token.init(.identifier, input, "id"),
        Token.init(.number, input, "5"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "not let-in" {
    const input = "letlet inin letin let-in";
    const tokens = [_]Token{
        Token.init(.identifier, input, "letlet"),
        Token.init(.identifier, input, "inin"),
        Token.init(.identifier, input, "letin"),
        Token.init(.let, input, "let"),
        Token.init(.minus, input, "-"),
        Token.init(.in, input, "in"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "if then else" {
    const input = "if 1 then 2 else 3";
    const tokens = [_]Token{
        Token.init(.@"if", input, "if"),
        Token.init(.number, input, "1"),
        Token.init(.then, input, "then"),
        Token.init(.number, input, "2"),
        Token.init(.@"else", input, "else"),
        Token.init(.number, input, "3"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "boolean" {
    const input = "true false";
    const tokens = [_]Token{
        Token.init(.true, input, "true"),
        Token.init(.false, input, "false"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "operators" {
    const input = "x + y * z - w / 2";
    const tokens = [_]Token{
        Token.init(.identifier, input, "x"),
        Token.init(.plus, input, "+"),
        Token.init(.identifier, input, "y"),
        Token.init(.star, input, "*"),
        Token.init(.identifier, input, "z"),
        Token.init(.minus, input, "-"),
        Token.init(.identifier, input, "w"),
        Token.init(.slash, input, "/"),
        Token.init(.number, input, "2"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "equality operators" {
    const input = "1 == 2 != 3";
    const tokens = [_]Token{
        Token.init(.number, input, "1"),
        Token.init(.equal, input, "=="),
        Token.init(.number, input, "2"),
        Token.init(.not_equal, input, "!="),
        Token.init(.number, input, "3"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "line comment only" {
    const input = "# hello";
    const tokens = [_]Token{
        Token.init(.comment, input, "# hello"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "comment then identifier" {
    const input = "# hello\nx";
    const tokens = [_]Token{
        Token.init(.comment, input, "# hello"),
        Token.init(.identifier, input, "x"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "inline comment after token" {
    const input = "x # c\ny";
    const tokens = [_]Token{
        Token.init(.identifier, input, "x"),
        Token.init(.comment, input, "# c"),
        Token.init(.identifier, input, "y"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "comment at EOF without newline" {
    const input = "1#end";
    const tokens = [_]Token{
        Token.init(.number, input, "1"),
        Token.init(.comment, input, "#end"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "empty string" {
    const input = "\"\"";
    const tokens = [_]Token{
        Token.init(.string, input, "\"\""),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "string unicode" {
    const input = "\"hello#world!@$%^&*()λ∀∃∈∉\"";
    const tokens = [_]Token{
        Token.init(.string, input, "\"hello#world!@$%^&*()λ∀∃∈∉\""),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "multiple strings" {
    const input = "\"hello world!\" \"\\x. x\"";
    const tokens = [_]Token{
        Token.init(.string, input, "\"hello world!\""),
        Token.init(.string, input, "\"\\x. x\""),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "string with identifiers" {
    const input = "x\"string\"y";
    const tokens = [_]Token{
        Token.init(.identifier, input, "x"),
        Token.init(.string, input, "\"string\""),
        Token.init(.identifier, input, "y"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "empty open string" {
    const input = "\"";
    const tokens = [_]Token{
        Token.init(.string_open, input, "\""),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "open string " {
    const input = "\"hello";
    const tokens = [_]Token{
        Token.init(.string_open, input, "\"hello"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "plus (and other operators) split identifiers" {
    const input = "x+y x++y hello+world x-y x*y x/x";
    const tokens = [_]Token{
        Token.init(.identifier, input, "x"),
        Token.init(.plus, input, "+"),
        Token.init(.identifier, input, "y"),
        Token.init(.identifier, input, "x"),
        Token.init(.concat, input, "++"),
        Token.init(.identifier, input, "y"),
        Token.init(.identifier, input, "hello"),
        Token.init(.plus, input, "+"),
        Token.init(.identifier, input, "world"),
        Token.init(.minus, input, "-"),
        Token.init(.identifier, input, "x"),
        Token.init(.star, input, "*"),
        Token.init(.identifier, input, "y"),
        Token.init(.identifier, input, "x"),
        Token.init(.slash, input, "/"),
        Token.init(.identifier, input, "y"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}
