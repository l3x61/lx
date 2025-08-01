const std = @import("std");
const Utf8View = std.unicode.Utf8View;
const Utf8Iterator = std.unicode.Utf8Iterator;
const parseFloat = std.fmt.parseFloat;
const print = std.debug.print;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const fmtSliceEscapeUpper = std.fmt.fmtSliceEscapeUpper;

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

iterator: Utf8Iterator,

pub fn init(input: []const u8) error{InvalidUtf8}!Lexer {
    var utf8_view = try Utf8View.init(input);
    return Lexer{ .iterator = utf8_view.iterator() };
}

pub fn nextToken(self: *Lexer) Token {
    const iterator = &self.iterator;

    // ...
    consumeWhile(iterator, isSpace);

    const start = iterator.i;

    const codepoint = iterator.nextCodepoint() orelse
        return Token.init(.eof, "");

    // ...
    switch (codepoint) {
        '\\', 'λ' => return Token.init(.lambda, iterator.bytes[start..iterator.i]),
        '.' => return Token.init(.dot, iterator.bytes[start..iterator.i]),
        '=' => return Token.init(.equal, iterator.bytes[start..iterator.i]),
        '(' => return Token.init(.lparen, iterator.bytes[start..iterator.i]),
        ')' => return Token.init(.rparen, iterator.bytes[start..iterator.i]),
        else => {},
    }

    // ...
    consumeWhile(iterator, isSymbol);
    const lexeme = iterator.bytes[start..iterator.i];

    // if lexeme matches a keyword then token=keyword else ...
    if (keywords_map.get(lexeme)) |keyword_tag| {
        return Token.init(keyword_tag, lexeme);
    }

    //if lexeme matches a number then token=number else token=symbol
    _ = parseFloat(f64, lexeme) catch return Token.init(.symbol, lexeme);
    return Token.init(.number, lexeme);
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

fn isSymbol(codepoint: u21) bool {
    return !isSpace(codepoint) and
        codepoint != '.' and
        codepoint != '(' and
        codepoint != ')' and
        codepoint != '\\' and
        codepoint != 'λ';
}

fn runTest(input: []const u8, tokens: []const Token) !void {
    var lexer = try Lexer.init(input);

    for (0.., tokens) |i, expected| {
        const actual = lexer.nextToken();
        expect(expected.equal(actual)) catch |err| {
            print(ansi.red ++ "error: " ++ ansi.reset, .{});
            print("at token {d} of {d} in `{s}`\n", .{ i, tokens.len, fmtSliceEscapeUpper(input) });
            print("expected: {s}\n", .{expected});
            print("     got: {s}\n\n", .{actual});
            return err;
        };
    }
}

test "empty" {
    const input = "";
    const tokens = [_]Token{
        Token.init(.eof, ""),
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

test "symbol" {
    const input = "abc";
    const tokens = [_]Token{
        Token.init(.symbol, "abc"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "symbols" {
    const input = "a b c";
    const tokens = [_]Token{
        Token.init(.symbol, "a"),
        Token.init(.symbol, "b"),
        Token.init(.symbol, "c"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "lambda with dot" {
    const input = "\\x.x";
    const tokens = [_]Token{
        Token.init(.lambda, "\\"),
        Token.init(.symbol, "x"),
        Token.init(.dot, "."),
        Token.init(.symbol, "x"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "lambda with unicode λ" {
    const input = "λx.x";
    const tokens = [_]Token{
        Token.init(.lambda, "λ"),
        Token.init(.symbol, "x"),
        Token.init(.dot, "."),
        Token.init(.symbol, "x"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "let in" {
    const input = "let id = λx.x in id 5";
    const tokens = [_]Token{
        Token.init(.let, "let"),
        Token.init(.symbol, "id"),
        Token.init(.equal, "="),
        Token.init(.lambda, "λ"),
        Token.init(.symbol, "x"),
        Token.init(.dot, "."),
        Token.init(.symbol, "x"),
        Token.init(.in, "in"),
        Token.init(.symbol, "id"),
        Token.init(.number, "5"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "not let-in" {
    const input = "letlet inin letin let-in";
    const tokens = [_]Token{
        Token.init(.symbol, "letlet"),
        Token.init(.symbol, "inin"),
        Token.init(.symbol, "letin"),
        Token.init(.symbol, "let-in"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "if then else" {
    const input = "if 1 then 2 else 3";
    const tokens = [_]Token{
        Token.init(.@"if", "if"),
        Token.init(.number, "1"),
        Token.init(.then, "then"),
        Token.init(.number, "2"),
        Token.init(.@"else", "else"),
        Token.init(.number, "3"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}

test "null true false" {
    const input = "null true false";
    const tokens = [_]Token{
        Token.init(.null, "null"),
        Token.init(.true, "true"),
        Token.init(.false, "false"),
        Token.init(.eof, ""),
    };
    try runTest(input, &tokens);
}
