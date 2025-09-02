const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const testing = std.testing;

const log = std.log.scoped(.parser);

const expect = testing.expect;
const expectError = testing.expectError;

const ansi = @import("ansi.zig");
const Lexer = @import("Lexer.zig");
const Node = @import("node.zig").Node;
const Token = @import("Token.zig");

const Parser = @This();

gpa: Allocator,
lexer: Lexer,
token: Token,

pub fn init(ator: Allocator, input: []const u8) !Parser {
    var lexer = try Lexer.init(input);

    var token = lexer.nextToken();
    while (token.tag == .comment) token = lexer.nextToken();

    return Parser{
        .gpa = ator,
        .lexer = lexer,
        .token = token,
    };
}

pub fn parse(self: *Parser) !*Node {
    return self.program();
}

fn nextToken(self: *Parser, expected: []const Token.Tag) !Token {
    const token = self.token;
    self.token = self.lexer.nextToken();

    while (self.token.tag == .comment) self.token = self.lexer.nextToken();

    if (!token.isOneOf(expected)) {
        log.err("expected {any} but got {f}\n", .{ expected, token.tag });
        return error.SyntaxError;
    }
    return token;
}

/// ```
/// program
///     = [ expression ]
///     .
/// ```
fn program(self: *Parser) !*Node {
    const node = try Node.Program.init(self.gpa, null);
    errdefer node.deinit(self.gpa);

    if (self.token.tag != .eof) {
        node.program.expression = try self.expression();
    }
    _ = try self.nextToken(&[_]Token.Tag{.eof});
    return node;
}

/// ```
/// expression
///     = binding
///     | selection
///     | equality
///     .
/// ```
fn expression(self: *Parser) anyerror!*Node {
    return switch (self.token.tag) {
        .let => self.binding(),
        .@"if" => self.selection(),
        else => self.equality(),
    };
}

/// ```
/// equality
///     = additive { ("==" | "!=") additive }
///     .
/// ```
fn equality(self: *Parser) !*Node {
    var left = try self.additive();
    errdefer left.deinit(self.gpa);

    while (true) {
        switch (self.token.tag) {
            .equal, .not_equal => {
                const operator = try self.nextToken(&[_]Token.Tag{ .equal, .not_equal });
                const right = try self.additive();
                errdefer right.deinit(self.gpa);
                left = try Node.Binary.init(self.gpa, left, operator, right);
            },
            else => break,
        }
    }
    return left;
}

/// ```
/// binding
///     = "let" IDENTIFIER "=" expression "in" expression
///     .
/// ```
// TODO: multiple bindings per let
//       eg: let I=E_1 { and I=E_N } in E_n+1
fn binding(self: *Parser) !*Node {
    _ = try self.nextToken(&[_]Token.Tag{.let});

    const name = try self.nextToken(&[_]Token.Tag{.identifier});

    _ = try self.nextToken(&[_]Token.Tag{.assign});
    const value = try self.expression();
    errdefer value.deinit(self.gpa);

    _ = try self.nextToken(&[_]Token.Tag{.in});
    const body = try self.expression();
    errdefer body.deinit(self.gpa);

    return Node.Binding.init(self.gpa, name, value, body);
}

/// ```
/// selection
///     = "if" expression "then" expression "else" expression
///     .
/// ```
fn selection(self: *Parser) !*Node {
    _ = try self.nextToken(&[_]Token.Tag{.@"if"});
    const condition = try self.expression();
    errdefer condition.deinit(self.gpa);

    _ = try self.nextToken(&[_]Token.Tag{.then});
    const consequent = try self.expression();
    errdefer consequent.deinit(self.gpa);

    _ = try self.nextToken(&[_]Token.Tag{.@"else"});
    const alternate = try self.expression();
    errdefer alternate.deinit(self.gpa);

    return Node.Selection.init(self.gpa, condition, consequent, alternate);
}

/// ```
/// function
///     = ("\\" | "λ") IDENTIFIER "." expression
///     .
/// ```
// TODO: allow multiple parameters
//       eg: \ { I . } E
fn function(self: *Parser) !*Node {
    _ = try self.nextToken(&[_]Token.Tag{.lambda});
    const parameter = try self.nextToken(&[_]Token.Tag{.identifier});
    _ = try self.nextToken(&[_]Token.Tag{.dot});
    const body = try self.expression();
    errdefer body.deinit(self.gpa);

    return Node.Function.init(self.gpa, parameter, body);
}

/// ```
/// additive
///     = multiplicative { ("+" | "-") multiplicative }
///     .
/// ```
fn additive(self: *Parser) !*Node {
    var left = try self.multiplicative();
    errdefer left.deinit(self.gpa);

    while (true) {
        switch (self.token.tag) {
            .plus, .minus => {
                const operator = try self.nextToken(&[_]Token.Tag{ .plus, .minus });
                const right = try self.multiplicative();
                errdefer right.deinit(self.gpa);
                left = try Node.Binary.init(self.gpa, left, operator, right);
            },
            else => break,
        }
    }
    return left;
}

/// ```
/// multiplicative
///     = application { ("*" | "/") application }
///     .
/// ```
fn multiplicative(self: *Parser) !*Node {
    var left = try self.application();
    errdefer left.deinit(self.gpa);

    while (true) {
        switch (self.token.tag) {
            .star, .slash => {
                const operator = try self.nextToken(&[_]Token.Tag{ .star, .slash });
                const right = try self.application();
                errdefer right.deinit(self.gpa);
                left = try Node.Binary.init(self.gpa, left, operator, right);
            },
            else => break,
        }
    }
    return left;
}

/// ```
/// application
///     = primary { primary }
///     .
/// ```
fn application(self: *Parser) !*Node {
    var left = try self.primary();
    errdefer left.deinit(self.gpa);

    while (true) {
        switch (self.token.tag) {
            .null, .true, .false, .lambda, .number, .identifier, .lparen => {
                const right = try self.primary();
                errdefer right.deinit(self.gpa);
                left = try Node.Application.init(self.gpa, left, right);
            },
            else => break,
        }
    }
    return left;
}

/// ```
/// primary
///     = "null"
///     | "true"
///     | "false"
///     | NUMBER
///     | SYMBOL
///     | function
///     | "(" expression ")"
///     .
/// ```
fn primary(self: *Parser) !*Node {
    return switch (self.token.tag) {
        .null, .true, .false, .number, .identifier => {
            const token = try self.nextToken(&[_]Token.Tag{ .null, .true, .false, .number, .identifier });
            return Node.Primary.init(self.gpa, token);
        },
        .lambda => {
            return self.function();
        },
        .lparen => {
            _ = try self.nextToken(&[_]Token.Tag{.lparen});
            const node = try self.expression();
            errdefer node.deinit(self.gpa);
            _ = try self.nextToken(&[_]Token.Tag{.rparen});
            return node;
        },
        else => {
            _ = try self.nextToken(&[_]Token.Tag{ .null, .true, .false, .number, .identifier, .lambda, .lparen });
            return error.SyntaxError;
        },
    };
}

fn runTest(input: []const u8, expected: *Node) !void {
    const ator = testing.allocator;
    defer expected.deinit(ator);

    var parser = try Parser.init(ator, input);

    var actual = try parser.parse();
    defer actual.deinit(ator);

    expect(actual.equal(expected)) catch {
        print("{s}error:{s} expected: {f} but got {f}\n", .{ ansi.red, ansi.reset, expected, actual });
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
        try Node.Primary.init(testing.allocator, Token.init(.number, input, "123")),
    );
    try runTest(input, expected);
}

test "function" {
    const input = "λx. x";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Function.init(
            testing.allocator,
            Token.init(.identifier, input, "x"),
            try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "x")),
        ),
    );
    try runTest(input, expected);
}

test "nested lambdas" {
    const input = "λx. λy. x";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Function.init(
            testing.allocator,
            Token.init(.identifier, input, "x"),
            try Node.Function.init(
                testing.allocator,
                Token.init(.identifier, input, "y"),
                try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "x")),
            ),
        ),
    );
    try runTest(input, expected);
}

test "incomplete function 1" {
    const input = "λ";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "incomplete function 2" {
    const input = "λx";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "incomplete function 3" {
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
            try Node.Function.init(
                testing.allocator,
                Token.init(.identifier, input, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "x")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "123")),
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
                    try Node.Function.init(
                        testing.allocator,
                        Token.init(.identifier, input, "x"),
                        try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "x")),
                    ),
                    try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                ),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
        ),
    );
    try runTest(input, expected);
}

test "binding" {
    const input = "let one = 1 in one";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binding.init(
            testing.allocator,
            Token.init(.identifier, input, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "one")),
        ),
    );
    try runTest(input, expected);
}

test "equal" {
    const input = "1 == 2";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.equal, input, "=="),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
        ),
    );
    try runTest(input, expected);
}

test "not equal" {
    const input = "1 != 2";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.not_equal, input, "!="),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
        ),
    );
    try runTest(input, expected);
}

test "nested binding" {
    const input =
        \\let one = 1 in
        \\let two = 2 in
        \\  one two
    ;
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binding.init(
            testing.allocator,
            Token.init(.identifier, input, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            try Node.Binding.init(
                testing.allocator,
                Token.init(.identifier, input, "two"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
                try Node.Application.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "one")),
                    try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "two")),
                ),
            ),
        ),
    );
    try runTest(input, expected);
}

test "let without in is error" {
    const input = "let one = 1";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "if then else" {
    const input = "if 1 then 2 else 3";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Selection.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
        ),
    );
    try runTest(input, expected);
}

test "fail to apply selection" {
    // selection has a lower precedence than application
    // hence EOF will be expected after parsing the function
    const input = "(\\x. x) if 1 then 2 else 3";
    var parser = try Parser.init(testing.allocator, input);
    try expectError(error.SyntaxError, parser.parse());
}

test "apply to selection" {
    const input = "(\\x. x) (if 1 then 2 else 3)";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Function.init(
                testing.allocator,
                Token.init(.identifier, input, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "x")),
            ),
            try Node.Selection.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
            ),
        ),
    );
    try runTest(input, expected);
}

test "literals" {
    const input = "if null then true else false";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Selection.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.null, input, "null")),
            try Node.Primary.init(testing.allocator, Token.init(.true, input, "true")),
            try Node.Primary.init(testing.allocator, Token.init(.false, input, "false")),
        ),
    );
    try runTest(input, expected);
}

test "apply to literals" {
    const input = "fn true false";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Application.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "fn")),
                try Node.Primary.init(testing.allocator, Token.init(.true, input, "true")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.false, input, "false")),
        ),
    );
    try runTest(input, expected);
}

test "multiplication precedence over addition" {
    const input = "1 + 2 * 3";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.plus, input, "+"),
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
                Token.init(.star, input, "*"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
            ),
        ),
    );
    try runTest(input, expected);
}

test "division precedence over subtraction" {
    const input = "10 - 6 / 2";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "10")),
            Token.init(.minus, input, "-"),
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "6")),
                Token.init(.slash, input, "/"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            ),
        ),
    );
    try runTest(input, expected);
}

test "left associativity of addition" {
    const input = "1 + 2 + 3";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                Token.init(.plus, input, "+"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            ),
            Token.init(.plus, input, "+"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
        ),
    );
    try runTest(input, expected);
}

test "left associativity of multiplication" {
    const input = "2 * 3 * 4";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
                Token.init(.star, input, "*"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
            ),
            Token.init(.star, input, "*"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "4")),
        ),
    );
    try runTest(input, expected);
}

test "arithmetic expression" {
    const input = "1 + x * 3 - y / 2";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                Token.init(.plus, input, "+"),
                try Node.Binary.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "x")),
                    Token.init(.star, input, "*"),
                    try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
                ),
            ),
            Token.init(.minus, input, "-"),
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.identifier, input, "y")),
                Token.init(.slash, input, "/"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            ),
        ),
    );
    try runTest(input, expected);
}

test "parentheses override precedence" {
    const input = "(1 + 2) * 3";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                Token.init(.plus, input, "+"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            ),
            Token.init(.star, input, "*"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
        ),
    );
    try runTest(input, expected);
}

test "comment" {
    const input = "# comment\n1 + 2";
    const expected = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.plus, input, "+"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
        ),
    );
    try runTest(input, expected);
}
