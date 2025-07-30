const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;

const ansi = @import("ansi.zig");
const Lexer = @import("Lexer.zig");
const Node = @import("node.zig").Node;
const Token = @import("Token.zig");

const Parser = @This();

allocator: Allocator,
lexer: Lexer,
token: Token,

pub fn init(allocator: Allocator, input: []const u8) !Parser {
    var lexer = try Lexer.init(input);
    const token = lexer.nextToken();
    return Parser{
        .allocator = allocator,
        .lexer = lexer,
        .token = token,
    };
}

pub fn parse(self: *Parser) !*Node {
    return self.program();
}

fn eatToken(self: *Parser, expected: []const Token.Tag) !Token {
    const token = self.token;
    self.token = self.lexer.nextToken();

    if (!token.isOneOf(expected)) {
        print("expected {s} but got {s}\n", .{ expected, token });
        return error.SyntaxError;
    }
    return token;
}

fn program(self: *Parser) !*Node {
    const node = try Node.Program.init(self.allocator, null);
    errdefer node.deinit(self.allocator);

    if (self.token.tag != .eof) node.program.expression = try self.expression();
    return node;
}

fn expression(self: *Parser) anyerror!*Node {
    return switch (self.token.tag) {
        .let => self.letIn(),
        .lambda => self.abstraction(),
        .number, .symbol, .lparen => self.application(),
        else => return error.SyntaxError,
    };
}

fn letIn(self: *Parser) !*Node {
    _ = try self.eatToken(&[_]Token.Tag{.let});
    const name = try self.eatToken(&[_]Token.Tag{.symbol});
    _ = try self.eatToken(&[_]Token.Tag{.equal});
    const value = try self.expression();
    errdefer value.deinit(self.allocator);
    _ = try self.eatToken(&[_]Token.Tag{.in});
    const body = try self.expression();
    errdefer body.deinit(self.allocator);

    return Node.LetIn.init(self.allocator, name, value, body);
}

fn abstraction(self: *Parser) !*Node {
    _ = try self.eatToken(&[_]Token.Tag{.lambda});
    const parameter = try self.eatToken(&[_]Token.Tag{.symbol});
    _ = try self.eatToken(&[_]Token.Tag{.dot});
    const body = try self.expression();
    errdefer body.deinit(self.allocator);

    return Node.Abstraction.init(self.allocator, parameter, body);
}

fn application(self: *Parser) !*Node {
    var left = try self.primary();
    errdefer left.deinit(self.allocator);

    while (true) {
        switch (self.token.tag) {
            .lambda, .number, .symbol, .lparen => {
                const right = try self.primary();
                errdefer right.deinit(self.allocator);
                left = try Node.Application.init(self.allocator, left, right);
            },
            else => break,
        }
    }
    return left;
}

fn primary(self: *Parser) !*Node {
    return switch (self.token.tag) {
        .lambda => self.abstraction(),
        .lparen => {
            _ = try self.eatToken(&[_]Token.Tag{.lparen});
            const node = try self.expression();
            errdefer node.deinit(self.allocator);
            _ = try self.eatToken(&[_]Token.Tag{.rparen});
            return node;
        },
        .number, .symbol => {
            const token = try self.eatToken(&[_]Token.Tag{ .number, .symbol });
            return Node.Primary.init(self.allocator, token);
        },
        else => self.application(),
    };
}

fn runTest(input: []const u8, expected: *Node) !void {
    const allocator = testing.allocator;
    defer expected.deinit(allocator);

    var parser = try Parser.init(allocator, input);

    var actual = try parser.parse();
    defer actual.deinit(allocator);

    expect(actual.equal(expected)) catch {
        print("{s}error:{s} expected: {s} but got {s}\n", .{ ansi.red, ansi.reset, expected, actual });
        return error.TestFailed;
    };
}

test "empty" {
    const input = "";
    const expected = try Node.Program.init(testing.allocator, null);
    try runTest(input, expected);
}

test "parenthesis" {
    const input = "(()()(()))";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "open parenthesis" {
    const input = "((())";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "closing parenthesis" {
    const input = "((())))";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "number" {
    const input = "123";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Primary.init(testing.allocator, Token.init(.number, "123")),
    );
    try runTest(input, expected);
}

test "lambda" {
    const input = "λx. x";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Abstraction.init(
            testing.allocator,
            Token.init(.symbol, "x"),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
        ),
    );
    try runTest(input, expected);
}

test "nested lambdas" {
    const input = "λx. λy. x";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Abstraction.init(
            testing.allocator,
            Token.init(.symbol, "x"),
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "y"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
            ),
        ),
    );
    try runTest(input, expected);
}

test "incomplete lambda 1" {
    const input = "λ";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "incomplete lambda 2" {
    const input = "λx";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "incomplete lambda 3" {
    const input = "λx.";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "application" {
    const input = "(λx. x) 123";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, "123")),
        ),
    );
    try runTest(input, expected);
}

test "applications" {
    const input = "(λx. x) 1 2 3";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Application.init(
                testing.allocator,
                try Node.Application.init(
                    testing.allocator,
                    try Node.Abstraction.init(
                        testing.allocator,
                        Token.init(.symbol, "x"),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
                    ),
                    try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
                ),
                try Node.Primary.init(testing.allocator, Token.init(.number, "2")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, "3")),
        ),
    );
    try runTest(input, expected);
}

test "let-in" {
    const input = "let one = 1 in one";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "one")),
        ),
    );
    try runTest(input, expected);
}

test "nested let-in" {
    const input =
        \\let one = 1 in
        \\let two = 2 in
        \\one two
    ;
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
            try Node.LetIn.init(
                testing.allocator,
                Token.init(.symbol, "two"),
                try Node.Primary.init(testing.allocator, Token.init(.number, "2")),
                try Node.Application.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, "one")),
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, "two")),
                ),
            ),
        ),
    );
    try runTest(input, expected);
}
