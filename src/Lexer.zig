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

const keywords_map = std.StaticStringMap(Token.Tag).initComptime(.{
    // keywords
    .{ "let", .let },
    .{ "in", .in },
    .{ "if", .@"if" },
    .{ "then", .then },
    .{ "else", .@"else" },
    // literals
    .{ "null", .null },
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

    consumeWhile(iterator, isSpace);

    const start = iterator.i;

    const codepoint = iterator.nextCodepoint() orelse {
        return Token.init(.eof, source, "");
    };

    if (codepoint == '"') {
        while (true) {
            const cp = iterator.nextCodepoint() orelse {
                return Token.init(.string_open, source, iterator.bytes[start..iterator.i]);
            };
            if (cp == '"') {
                return Token.init(.string, source, iterator.bytes[start..iterator.i]);
            }
        }
    }

    if (codepoint == '#') {
        consumeWhile(iterator, struct {
            fn notNewline(cp: u21) bool {
                return cp != '\n';
            }
        }.notNewline);
        return Token.init(.comment, source, iterator.bytes[start..iterator.i]);
    }

    if (codepoint == '=') {
        if (iterator.i < iterator.bytes.len and iterator.bytes[iterator.i] == '=') {
            iterator.i += 1;
            return Token.init(.equal, source, iterator.bytes[start..iterator.i]);
        }
        return Token.init(.assign, source, iterator.bytes[start..iterator.i]);
    }

    if (codepoint == '!') {
        if (iterator.i < iterator.bytes.len and iterator.bytes[iterator.i] == '=') {
            iterator.i += 1;
            return Token.init(.not_equal, source, iterator.bytes[start..iterator.i]);
        }
    }

    if (getSpecialToken(codepoint)) |tag| {
        return Token.init(tag, source, iterator.bytes[start..iterator.i]);
    }

    consumeWhile(iterator, isIdentifier);
    const lexeme = iterator.bytes[start..iterator.i];

    if (keywords_map.get(lexeme)) |keyword_tag| {
        return Token.init(keyword_tag, source, lexeme);
    }

    _ = parseFloat(f64, lexeme) catch {
        return Token.init(.identifier, source, lexeme);
    };
    return Token.init(.number, source, lexeme);
}

fn consumeWhile(iterator: *Utf8Iterator, predicate: fn (u21) bool) void {
    while (true) {
        const i = iterator.i;
        const codepoint = iterator.nextCodepoint() orelse return;
        if (!predicate(codepoint)) {
            iterator.i = i;
            return;
        }
    }
}

fn isSpace(codepoint: u21) bool {
    return switch (codepoint) {
        '\t',
        '\n',
        '\r',
        ' ',
        0x0C,
        0x85,
        0xA0,
        => true,
        else => false,
    };
}

fn getSpecialToken(codepoint: u21) ?Token.Tag {
    return switch (codepoint) {
        '\\', 'λ' => .lambda,
        '.' => .dot,
        '=' => .assign,
        '(' => .lparen,
        ')' => .rparen,
        '+' => .plus,
        '-' => .minus,
        '*' => .star,
        '/' => .slash,
        else => null,
    };
}

fn isIdentifier(codepoint: u21) bool {
    return codepoint != '#' and codepoint != '"' and !isSpace(codepoint) and getSpecialToken(codepoint) == null;
}

fn runTest(input: []const u8, tokens: []const Token) !void {
    var lexer = try Lexer.init(input);

    const escaped = hexEscape(input, .upper);
    for (0.., tokens) |i, expected| {
        const actual = lexer.nextToken();

        expect(expected.equal(actual)) catch |err| {
            print(ansi.red ++ "error: " ++ ansi.reset, .{});
            print("at token {d} of {d} in `{s}`\n", .{ i, tokens.len, escaped.data.bytes });
            print("expected: {f}\n", .{expected.tag});
            print("     got: {f}\n\n", .{actual.tag});
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

test "null true false" {
    const input = "null true false";
    const tokens = [_]Token{
        Token.init(.null, input, "null"),
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
