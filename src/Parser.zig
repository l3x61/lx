const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const fs = std.fs;

const log = std.log.scoped(.parser);

const Lexer = @import("Lexer.zig");
const Node = @import("node.zig").Node;
const Branch = @import("node.zig").Branch;
const Pattern = @import("node.zig").Pattern;
const FunctionBody = @import("node.zig").FunctionBody;
const Token = @import("Token.zig");

const Parser = @This();

allocator: Allocator,
tokens: []Token,
index: usize,

pub fn init(allocator: Allocator, source: []const u8) !Parser {
    var lexer = try Lexer.init(source);
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);

    while (true) {
        const token = lexer.nextToken();
        if (token.tag != .comment) try tokens.append(allocator, token);
        if (token.tag == .eof) break;
    }

    return .{
        .allocator = allocator,
        .tokens = try tokens.toOwnedSlice(allocator),
        .index = 0,
    };
}

pub fn deinit(self: *Parser) void {
    self.allocator.free(self.tokens);
}

// ```
// program = expression EOF .
// ```
pub fn parse(self: *Parser) !*Node {
    self.skipNewlines();
    const expression = try self.parseExpression();
    errdefer expression.deinit(self.allocator);
    self.skipNewlines();
    _ = try self.expect(.eof);
    return Node.create(self.allocator, .{
        .program = .{ .expression = expression },
    });
}

fn current(self: *const Parser) Token {
    return self.tokens[self.index];
}

fn peek(self: *const Parser, offset: usize) Token {
    const next = self.index + offset;
    if (next >= self.tokens.len) return self.tokens[self.tokens.len - 1];
    return self.tokens[next];
}

fn advance(self: *Parser) Token {
    const token = self.current();
    if (self.index + 1 < self.tokens.len) self.index += 1;
    return token;
}

fn expect(self: *Parser, tag: Token.Tag) !Token {
    const token = self.current();
    if (token.tag != tag) {
        log.debug("expected {f} but got {f}\n", .{ tag, token.tag });
        return error.SyntaxError;
    }
    return self.advance();
}

fn match(self: *Parser, tag: Token.Tag) bool {
    if (self.current().tag != tag) return false;
    _ = self.advance();
    return true;
}

fn skipNewlines(self: *Parser) void {
    while (self.current().tag == .newline) _ = self.advance();
}

// ```
// expression
//     = let-binding ";" expression
//     | non-binding [ ";" expression ]
//     .
// ```
fn parseExpression(self: *Parser) anyerror!*Node {
    self.skipNewlines();

    if (self.current().tag == .let) {
        return self.parseBindingExpression();
    }

    const first = try self.parseNonBinding();
    errdefer first.deinit(self.allocator);

    self.skipNewlines();
    if (!self.match(.semicolon)) return first;

    self.skipNewlines();
    const second = try self.parseExpression();
    errdefer second.deinit(self.allocator);
    return Node.create(self.allocator, .{
        .sequence = .{
            .first = first,
            .second = second,
        },
    });
}

// ```
// let-binding = "let" pattern "=" non-binding .
// ```
fn parseBindingExpression(self: *Parser) anyerror!*Node {
    _ = try self.expect(.let);
    const pattern = try self.parsePattern();
    errdefer pattern.deinit(self.allocator);

    self.skipNewlines();
    _ = try self.expect(.assign);
    const value = try self.parseNonBinding();
    errdefer value.deinit(self.allocator);

    self.skipNewlines();
    _ = try self.expect(.semicolon);
    self.skipNewlines();
    const body = try self.parseExpression();
    errdefer body.deinit(self.allocator);

    return Node.create(self.allocator, .{
        .binding = .{
            .pattern = pattern,
            .value = value,
            .body = body,
        },
    });
}

// ```
// non-binding = binary .
// ```
fn parseNonBinding(self: *Parser) anyerror!*Node {
    return self.parseBinary(1);
}

// ```
// binary = comparison .
// comparison = concat { ("==" | "!=" | "<" | ">" | "<=" | ">=") concat } .
// concat = addition [ "++" concat ] .
// addition = multiplication { ("+" | "-") multiplication } .
// multiplication = unary { ("*" | "/" | "%") unary } .
// ```
fn parseBinary(self: *Parser, min_precedence: u8) anyerror!*Node {
    var left = try self.parseUnary();
    errdefer left.deinit(self.allocator);

    while (true) {
        self.skipNewlines();

        const operator = self.current();
        const precedence = infixPrecedence(operator.tag) orelse break;
        if (precedence < min_precedence) break;

        _ = self.advance();
        const next_min = if (operator.tag == .concat) precedence else precedence + 1;
        left = blk: {
            const right = try self.parseBinary(next_min);
            errdefer right.deinit(self.allocator);

            break :blk try Node.create(self.allocator, .{
                .binary = .{
                    .left = left,
                    .operator = operator,
                    .right = right,
                },
            });
        };
    }

    return left;
}

// ```
// unary = [ "-" | "!" ] application .
// ```
fn parseUnary(self: *Parser) anyerror!*Node {
    self.skipNewlines();
    return switch (self.current().tag) {
        .minus, .not => blk: {
            const operator = self.advance();
            const operand = try self.parseUnary();
            errdefer operand.deinit(self.allocator);
            break :blk try Node.create(self.allocator, .{
                .unary = .{
                    .operator = operator,
                    .operand = operand,
                },
            });
        },
        else => self.parseApplication(),
    };
}

// ```
// application = primary { "(" [ arguments ] ")" } .
// ```
fn parseApplication(self: *Parser) anyerror!*Node {
    var callee = try self.parsePrimary();
    errdefer callee.deinit(self.allocator);

    while (true) {
        self.skipNewlines();
        if (self.current().tag != .lparen) break;

        callee = blk: {
            const arguments = try self.parseArguments();
            errdefer deinitNodeSlice(self.allocator, arguments);

            break :blk try Node.create(self.allocator, .{
                .call = .{
                    .callee = callee,
                    .arguments = arguments,
                },
            });
        };
    }

    return callee;
}

// ```
// primary
//     = literal
//     | identifier
//     | list
//     | range
//     | block
//     | function
//     | "(" expression ")"
//     .
// ```
fn parsePrimary(self: *Parser) anyerror!*Node {
    self.skipNewlines();
    const token = self.current();

    return switch (token.tag) {
        .identifier => blk: {
            _ = self.advance();
            break :blk try Node.create(self.allocator, .{ .identifier = token });
        },
        .number, .string, .true, .false => blk: {
            _ = self.advance();
            break :blk try Node.create(self.allocator, .{ .literal = token });
        },
        .lparen => if (self.isFunctionStart()) self.parseFunction() else blk: {
            _ = self.advance();
            const expression = try self.parseExpression();
            errdefer expression.deinit(self.allocator);
            _ = try self.expect(.rparen);
            break :blk expression;
        },
        .lbrace => self.parseBlock(),
        .lbracket => if (self.isRangeStart()) self.parseRange() else self.parseList(),
        else => {
            log.debug("unexpected token {f}\n", .{token.tag});
            return error.SyntaxError;
        },
    };
}

// ```
// function = "(" [ parameters ] ")" "{" function-body "}" .
// parameters = identifier { "," identifier } .
// function-body = expression | branches .
// ```
fn parseFunction(self: *Parser) anyerror!*Node {
    _ = try self.expect(.lparen);

    var parameters: std.ArrayList(Token) = .empty;
    defer parameters.deinit(self.allocator);

    self.skipNewlines();
    if (self.current().tag != .rparen) {
        while (true) {
            try parameters.append(self.allocator, try self.expect(.identifier));
            self.skipNewlines();
            if (!self.match(.comma)) break;
            self.skipNewlines();
        }
    }
    _ = try self.expect(.rparen);
    self.skipNewlines();
    _ = try self.expect(.lbrace);
    self.skipNewlines();

    if (self.current().tag == .rbrace) return error.SyntaxError;

    const body: FunctionBody = if (self.startsBranch())
        .{ .branches = try self.parseBranches() }
    else
        .{ .expression = try self.parseExpression() };
    errdefer {
        var owned_body = body;
        owned_body.deinit(self.allocator);
    }

    self.skipNewlines();
    _ = try self.expect(.rbrace);
    const owned_parameters = try parameters.toOwnedSlice(self.allocator);
    errdefer self.allocator.free(owned_parameters);

    return Node.create(self.allocator, .{
        .function = .{
            .parameters = owned_parameters,
            .body = body,
        },
    });
}

// ```
// branches = branch { "," branch } [ "," ] .
// ```
fn parseBranches(self: *Parser) anyerror![]*Branch {
    var branches: std.ArrayList(*Branch) = .empty;
    errdefer {
        for (branches.items) |branch| branch.deinit(self.allocator);
        branches.deinit(self.allocator);
    }

    while (true) {
        try branches.append(self.allocator, try self.parseBranch());

        self.skipNewlines();
        if (self.current().tag == .rbrace) break;
        _ = try self.expect(.comma);

        self.skipNewlines();
        if (self.current().tag == .rbrace) break;
    }

    return try branches.toOwnedSlice(self.allocator);
}

// ```
// branch
//     = patterns [ "?" expression ] "=>" expression
//     | "?" expression "=>" expression
//     | "=>" expression
//     .
// ```
fn parseBranch(self: *Parser) anyerror!*Branch {
    if (self.match(.question)) {
        const guard = try self.parseExpression();
        errdefer guard.deinit(self.allocator);

        _ = try self.expect(.fat_arrow);
        const result = try self.parseExpression();
        errdefer result.deinit(self.allocator);
        return try Branch.create(self.allocator, null, guard, result);
    }

    if (self.match(.fat_arrow)) {
        const result = try self.parseExpression();
        errdefer result.deinit(self.allocator);
        return try Branch.create(self.allocator, null, null, result);
    }

    const patterns = try self.parsePatterns();
    errdefer {
        for (patterns) |pattern| pattern.deinit(self.allocator);
        self.allocator.free(patterns);
    }

    var guard: ?*Node = null;
    errdefer if (guard) |owned_guard| owned_guard.deinit(self.allocator);
    if (self.match(.question)) {
        guard = try self.parseExpression();
    }

    _ = try self.expect(.fat_arrow);
    const result = try self.parseExpression();
    errdefer result.deinit(self.allocator);

    return try Branch.create(self.allocator, patterns, guard, result);
}

// ```
// patterns = pattern { "," pattern } .
// ```
fn parsePatterns(self: *Parser) anyerror![]*Pattern {
    var patterns: std.ArrayList(*Pattern) = .empty;
    errdefer {
        for (patterns.items) |pattern| pattern.deinit(self.allocator);
        patterns.deinit(self.allocator);
    }

    try patterns.append(self.allocator, try self.parsePattern());
    while (true) {
        self.skipNewlines();
        if (!self.match(.comma)) break;
        self.skipNewlines();
        try patterns.append(self.allocator, try self.parsePattern());
    }

    return try patterns.toOwnedSlice(self.allocator);
}

// ```
// pattern
//     = "_"
//     | literal
//     | identifier
//     | "[" [ pattern-items ] "]"
//     | "(" pattern ")"
//     .
// ```
fn parsePattern(self: *Parser) anyerror!*Pattern {
    self.skipNewlines();
    const token = self.current();

    return switch (token.tag) {
        .underscore => blk: {
            _ = self.advance();
            break :blk try Pattern.create(self.allocator, .{ .wildcard = {} });
        },
        .identifier => blk: {
            _ = self.advance();
            break :blk try Pattern.create(self.allocator, .{ .identifier = token });
        },
        .number, .string, .true, .false => blk: {
            _ = self.advance();
            break :blk try Pattern.create(self.allocator, .{ .literal = token });
        },
        .lparen => blk: {
            _ = self.advance();
            const inner = try self.parsePattern();
            errdefer inner.deinit(self.allocator);
            _ = try self.expect(.rparen);
            break :blk try Pattern.create(self.allocator, .{ .group = inner });
        },
        .lbracket => self.parseListPattern(),
        else => error.SyntaxError,
    };
}

// ```
// pattern-items = spread-pattern | pattern { "," pattern } [ "," spread-pattern ] .
// spread-pattern = "..." pattern .
// ```
fn parseListPattern(self: *Parser) anyerror!*Pattern {
    _ = try self.expect(.lbracket);
    self.skipNewlines();

    var items: std.ArrayList(*Pattern) = .empty;
    errdefer {
        for (items.items) |item| item.deinit(self.allocator);
        items.deinit(self.allocator);
    }

    var spread: ?*Pattern = null;
    errdefer if (spread) |owned_spread| owned_spread.deinit(self.allocator);

    if (self.current().tag != .rbracket) {
        if (self.match(.spread)) {
            spread = try self.parsePattern();
        } else {
            try items.append(self.allocator, try self.parsePattern());
            while (true) {
                self.skipNewlines();
                if (!self.match(.comma)) break;
                self.skipNewlines();
                if (self.match(.spread)) {
                    spread = try self.parsePattern();
                    break;
                }
                try items.append(self.allocator, try self.parsePattern());
            }
        }
    }

    self.skipNewlines();
    _ = try self.expect(.rbracket);
    const owned_items = try items.toOwnedSlice(self.allocator);
    errdefer self.allocator.free(owned_items);

    return try Pattern.create(self.allocator, .{
        .list = .{
            .items = owned_items,
            .spread = spread,
        },
    });
}

// ```
// arguments = expression { "," expression } .
// ```
fn parseArguments(self: *Parser) anyerror![]*Node {
    _ = try self.expect(.lparen);
    self.skipNewlines();

    var arguments: std.ArrayList(*Node) = .empty;
    errdefer {
        for (arguments.items) |argument| argument.deinit(self.allocator);
        arguments.deinit(self.allocator);
    }

    if (self.current().tag != .rparen) {
        while (true) {
            try arguments.append(self.allocator, try self.parseExpression());
            self.skipNewlines();
            if (!self.match(.comma)) break;
            self.skipNewlines();
        }
    }

    _ = try self.expect(.rparen);
    return try arguments.toOwnedSlice(self.allocator);
}

// ```
// list = "[" [ list-items ] "]" .
// list-items = spread | expression { "," expression } [ "," spread ] .
// spread = "..." expression .
// ```
fn parseList(self: *Parser) anyerror!*Node {
    _ = try self.expect(.lbracket);
    self.skipNewlines();

    var items: std.ArrayList(*Node) = .empty;
    errdefer {
        for (items.items) |item| item.deinit(self.allocator);
        items.deinit(self.allocator);
    }

    var spread: ?*Node = null;
    errdefer if (spread) |owned_spread| owned_spread.deinit(self.allocator);

    if (self.current().tag != .rbracket) {
        if (self.match(.spread)) {
            spread = try self.parseExpression();
        } else {
            try items.append(self.allocator, try self.parseExpression());
            while (true) {
                self.skipNewlines();
                if (!self.match(.comma)) break;
                self.skipNewlines();
                if (self.match(.spread)) {
                    spread = try self.parseExpression();
                    break;
                }
                try items.append(self.allocator, try self.parseExpression());
            }
        }
    }

    self.skipNewlines();
    _ = try self.expect(.rbracket);
    const owned_items = try items.toOwnedSlice(self.allocator);
    errdefer self.allocator.free(owned_items);

    return try Node.create(self.allocator, .{
        .list = .{
            .items = owned_items,
            .spread = spread,
        },
    });
}

// ```
// range = "[" expression ".." expression "]" .
// ```
fn parseRange(self: *Parser) anyerror!*Node {
    _ = try self.expect(.lbracket);
    self.skipNewlines();

    const start = try self.parseExpression();
    errdefer start.deinit(self.allocator);

    _ = try self.expect(.range);
    const end = try self.parseExpression();
    errdefer end.deinit(self.allocator);

    _ = try self.expect(.rbracket);
    return try Node.create(self.allocator, .{
        .range = .{
            .start = start,
            .end = end,
        },
    });
}

// ```
// block = "{" expression "}" .
// ```
fn parseBlock(self: *Parser) anyerror!*Node {
    _ = try self.expect(.lbrace);
    self.skipNewlines();
    const expression = try self.parseExpression();
    errdefer expression.deinit(self.allocator);
    self.skipNewlines();
    _ = try self.expect(.rbrace);
    return try Node.create(self.allocator, .{
        .block = .{ .expression = expression },
    });
}

fn deinitNodeSlice(allocator: Allocator, items: []*Node) void {
    for (items) |item| item.deinit(allocator);
    allocator.free(items);
}

fn infixPrecedence(tag: Token.Tag) ?u8 {
    return switch (tag) {
        .equal, .not_equal, .greater, .greater_equal, .less, .less_equal => 1,
        .concat => 2,
        .plus, .minus => 3,
        .star, .slash, .percent => 4,
        else => null,
    };
}

fn isFunctionStart(self: *const Parser) bool {
    if (self.current().tag != .lparen) return false;

    var index = self.index + 1;
    if (index >= self.tokens.len) return false;

    if (self.tokens[index].tag == .rparen) {
        index += 1;
        return index < self.tokens.len and self.tokens[index].tag == .lbrace;
    }

    while (true) {
        if (index >= self.tokens.len or self.tokens[index].tag != .identifier) return false;
        index += 1;
        if (index >= self.tokens.len) return false;

        switch (self.tokens[index].tag) {
            .comma => index += 1,
            .rparen => {
                index += 1;
                return index < self.tokens.len and self.tokens[index].tag == .lbrace;
            },
            else => return false,
        }
    }
}

fn isRangeStart(self: *const Parser) bool {
    if (self.current().tag != .lbracket) return false;

    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var index = self.index + 1;

    while (index < self.tokens.len) : (index += 1) {
        const tag = self.tokens[index].tag;
        switch (tag) {
            .lparen => paren_depth += 1,
            .rparen => {
                if (paren_depth != 0) paren_depth -= 1;
            },
            .lbrace => brace_depth += 1,
            .rbrace => {
                if (brace_depth != 0) brace_depth -= 1;
            },
            .lbracket => bracket_depth += 1,
            .rbracket => {
                if (bracket_depth == 0 and paren_depth == 0 and brace_depth == 0) return false;
                if (bracket_depth != 0) bracket_depth -= 1;
            },
            .comma, .spread => if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) return false,
            .range => if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) return true,
            else => {},
        }
    }

    return false;
}

fn startsBranch(self: *const Parser) bool {
    const start = self.current().tag;
    if (start == .question or start == .fat_arrow) return true;
    if (!isPatternStart(start)) return false;

    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var index = self.index;

    while (index < self.tokens.len) : (index += 1) {
        const tag = self.tokens[index].tag;
        switch (tag) {
            .lparen => paren_depth += 1,
            .rparen => {
                if (paren_depth != 0) paren_depth -= 1;
            },
            .lbrace => brace_depth += 1,
            .rbrace => {
                if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) return false;
                if (brace_depth != 0) brace_depth -= 1;
            },
            .lbracket => bracket_depth += 1,
            .rbracket => {
                if (bracket_depth != 0) bracket_depth -= 1;
            },
            .fat_arrow => if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) return true,
            else => {},
        }
    }

    return false;
}

fn isPatternStart(tag: Token.Tag) bool {
    return switch (tag) {
        .underscore, .identifier, .number, .string, .true, .false, .lbracket, .lparen => true,
        else => false,
    };
}

fn expectParsesToSource(input: []const u8, expected: []const u8) !void {
    var parser = try Parser.init(testing.allocator, input);
    defer parser.deinit();

    const node = try parser.parse();
    defer node.deinit(testing.allocator);

    var buffer: std.Io.Writer.Allocating = .init(testing.allocator);
    defer buffer.deinit();
    try node.writeSource(&buffer.writer);
    try testing.expectEqualStrings(expected, buffer.written());
}

fn expectParsesToTree(input: []const u8, expected: []const u8) !void {
    var parser = try Parser.init(testing.allocator, input);
    defer parser.deinit();

    const node = try parser.parse();
    defer node.deinit(testing.allocator);

    var buffer: std.Io.Writer.Allocating = .init(testing.allocator);
    defer buffer.deinit();
    try node.writeTree(.{ .writer = &buffer.writer, .mode = .no_color });
    try testing.expectEqualStrings(expected, buffer.written());
}

test "literal program" {
    try expectParsesToSource("42", "42");
}

test "binding sequence" {
    try expectParsesToSource(
        \\let answer = 42;
        \\answer
    ,
        \\let answer = 42;
        \\answer
    );
}

test "function with single expression body" {
    try expectParsesToSource(
        \\let add = (x, y) { x + y };
        \\add(1, 2)
    ,
        \\let add = (x, y) { x + y };
        \\add(1, 2)
    );
}

test "function with branches" {
    try expectParsesToSource(
        \\let abs = (n) {
        \\    ? n >= 0 => n,
        \\    => -n
        \\};
        \\
        \\abs(-5)
    ,
        \\let abs = (n) {
        \\    ? n >= 0 => n,
        \\    => -n
        \\};
        \\abs(-5)
    );
}

test "overview example from spec" {
    try expectParsesToSource(
        \\let fizzbuzz = (n) {
        \\    ? n % 15 == 0 => print("FizzBuzz"),
        \\    ? n % 3 == 0 => print("Fizz"),
        \\    ? n % 5 == 0 => print("Buzz"),
        \\    => print(n)
        \\};
        \\
        \\let loop = (i, max) {
        \\    i, max ? i > max => print("Done."),
        \\    => {
        \\        fizzbuzz(i);
        \\        loop(i + 1, max)
        \\    }
        \\};
        \\
        \\loop(1, 15)
    ,
        \\let fizzbuzz = (n) {
        \\    ? n % 15 == 0 => print("FizzBuzz"),
        \\    ? n % 3 == 0 => print("Fizz"),
        \\    ? n % 5 == 0 => print("Buzz"),
        \\    => print(n)
        \\};
        \\let loop = (i, max) {
        \\    i, max ? i > max => print("Done."),
        \\    => {
        \\        fizzbuzz(i);
        \\        loop(i + 1, max)
        \\    }
        \\};
        \\loop(1, 15)
    );
}

test "patterns lists and spread" {
    try expectParsesToSource(
        \\let head = (xs) {
        \\    [x, ..._] => x,
        \\    [] => "empty"
        \\};
        \\head([10, 20, 30])
    ,
        \\let head = (xs) {
        \\    [x, ..._] => x,
        \\    [] => "empty"
        \\};
        \\head([10, 20, 30])
    );
}

test "operators precedence" {
    try expectParsesToSource(
        "1 + 2 * 3 == 7",
        "1 + 2 * 3 == 7",
    );
}

test "operators example from spec" {
    try expectParsesToSource(
        \\let classify = (n) {
        \\    ? n > 0 => "positive",
        \\    ? n < 0 => "negative",
        \\    => "zero"
        \\};
        \\
        \\classify(-3)
    ,
        \\let classify = (n) {
        \\    ? n > 0 => "positive",
        \\    ? n < 0 => "negative",
        \\    => "zero"
        \\};
        \\classify(-3)
    );
}

test "block and range" {
    try expectParsesToSource(
        \\{
        \\    let xs = [1..5];
        \\    [0, ...xs]
        \\}
    ,
        \\{
        \\    let xs = [1..5];
        \\    [0, ...xs]
        \\}
    );
}

test "block example from spec" {
    try expectParsesToSource(
        \\{
        \\    let square = (x) { x * x };
        \\    let y = 4;
        \\    square(y)
        \\}
    ,
        \\{
        \\    let square = (x) { x * x };
        \\    let y = 4;
        \\    square(y)
        \\}
    );
}

test "empty parameter function" {
    try expectParsesToSource(
        \\let constant = () { 1 + 2 };
        \\constant()
    ,
        \\let constant = () { 1 + 2 };
        \\constant()
    );
}

test "grouped pattern and literal forms" {
    try expectParsesToSource(
        \\let classify = (value) {
        \\    ("ok") => true,
        \\    3.14 => false,
        \\    _ => false
        \\};
        \\classify("ok")
    ,
        \\let classify = (value) {
        \\    ("ok") => true,
        \\    3.14 => false,
        \\    _ => false
        \\};
        \\classify("ok")
    );
}

test "tree output" {
    try expectParsesToTree(
        \\let answer = 42;
        \\answer
    ,
        \\program
        \\    binding
        \\        pattern: identifier answer
        \\        value: literal 42
        \\        body: identifier answer
        \\
    );
}

test "let requires continuation" {
    var parser = try Parser.init(testing.allocator, "let answer = 42");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "missing branch comma is an error" {
    var parser = try Parser.init(
        testing.allocator,
        \\(x) {
        \\    ? x > 0 => x
        \\    => -x
        \\}
    );
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "comments and newlines are ignored as whitespace" {
    try expectParsesToSource(
        \\# leading
        \\let answer = 42;
        \\# trailing
        \\answer
    ,
        \\let answer = 42;
        \\answer
    );
}

test "unary negation" {
    try expectParsesToSource("-42", "-42");
}

test "unary not" {
    try expectParsesToSource("!true", "!true");
}

test "double unary" {
    try expectParsesToSource("--x", "--x");
}

test "unary in binary expression" {
    try expectParsesToSource("-a + b", "-a + b");
}

test "string concatenation" {
    try expectParsesToSource(
        \\"hello" ++ " " ++ "world"
    ,
        \\"hello" ++ " " ++ "world"
    );
}

test "right associativity of concat" {
    try expectParsesToTree(
        \\"a" ++ "b" ++ "c"
    ,
        \\program
        \\    binary ++
        \\        left: literal "a"
        \\        right: binary ++
        \\            left: literal "b"
        \\            right: literal "c"
        \\
    );
}

test "nested function calls" {
    try expectParsesToSource("f(g(x))", "f(g(x))");
}

test "chained function calls" {
    try expectParsesToSource("f(1)(2)(3)", "f(1)(2)(3)");
}

test "call with no arguments" {
    try expectParsesToSource("f()", "f()");
}

test "multiple bindings" {
    try expectParsesToSource(
        \\let a = 1;
        \\let b = 2;
        \\let c = 3;
        \\a + b + c
    ,
        \\let a = 1;
        \\let b = 2;
        \\let c = 3;
        \\a + b + c
    );
}

test "sequence without binding" {
    try expectParsesToSource(
        \\print("hello");
        \\print("world")
    ,
        \\print("hello");
        \\print("world")
    );
}

test "nested blocks" {
    try expectParsesToSource(
        \\{
        \\    let x = {
        \\        let a = 1;
        \\        a + 1
        \\    };
        \\    x * 2
        \\}
    ,
        \\{
        \\    let x = {
        \\    let a = 1;
        \\    a + 1
        \\};
        \\    x * 2
        \\}
    );
}

test "empty list" {
    try expectParsesToSource("[]", "[]");
}

test "list with spread only" {
    try expectParsesToSource("[...xs]", "[...xs]");
}

test "list with items and spread" {
    try expectParsesToSource("[1, 2, ...rest]", "[1, 2, ...rest]");
}

test "range with expressions" {
    try expectParsesToSource("[1 + 0..2 * 5]", "[1 + 0..2 * 5]");
}

test "parenthesized expression" {
    try expectParsesToSource("(1 + 2) * 3", "(1 + 2) * 3");
}

test "parenthesized expression tree" {
    try expectParsesToTree("(1 + 2) * 3",
        \\program
        \\    binary *
        \\        left: binary +
        \\            left: literal 1
        \\            right: literal 2
        \\        right: literal 3
        \\
    );
}

test "pattern matching with boolean literals" {
    try expectParsesToSource(
        \\(x) {
        \\    true => "yes",
        \\    false => "no"
        \\}
    ,
        \\(x) {
        \\    true => "yes",
        \\    false => "no"
        \\}
    );
}

test "pattern matching with multiple parameters" {
    try expectParsesToSource(
        \\(a, b) {
        \\    0, 0 => "origin",
        \\    _, _ => "elsewhere"
        \\}
    ,
        \\(a, b) {
        \\    0, 0 => "origin",
        \\    _, _ => "elsewhere"
        \\}
    );
}

test "pattern with guard and value match" {
    try expectParsesToSource(
        \\(x) {
        \\    0 => "zero",
        \\    n ? n > 0 => "positive",
        \\    => "negative"
        \\}
    ,
        \\(x) {
        \\    0 => "zero",
        \\    n ? n > 0 => "positive",
        \\    => "negative"
        \\}
    );
}

test "nested list patterns" {
    try expectParsesToSource(
        \\(xs) {
        \\    [[a, b], ...rest] => a,
        \\    _ => 0
        \\}
    ,
        \\(xs) {
        \\    [[a, b], ...rest] => a,
        \\    _ => 0
        \\}
    );
}

test "higher order function" {
    try expectParsesToSource(
        \\let apply = (f, x) { f(x) };
        \\let double = (n) { n * 2 };
        \\apply(double, 5)
    ,
        \\let apply = (f, x) { f(x) };
        \\let double = (n) { n * 2 };
        \\apply(double, 5)
    );
}

test "closure returning function" {
    try expectParsesToSource(
        \\let make = (n) {
        \\    (x) { x + n }
        \\};
        \\make(5)(10)
    ,
        \\let make = (n) {
        \\    (x) { x + n }
        \\};
        \\make(5)(10)
    );
}

test "all comparison operators" {
    try expectParsesToSource("a == b", "a == b");
    try expectParsesToSource("a != b", "a != b");
    try expectParsesToSource("a < b", "a < b");
    try expectParsesToSource("a > b", "a > b");
    try expectParsesToSource("a <= b", "a <= b");
    try expectParsesToSource("a >= b", "a >= b");
}

test "all arithmetic operators" {
    try expectParsesToSource("a + b", "a + b");
    try expectParsesToSource("a - b", "a - b");
    try expectParsesToSource("a * b", "a * b");
    try expectParsesToSource("a / b", "a / b");
    try expectParsesToSource("a % b", "a % b");
}

test "operator precedence tree" {
    try expectParsesToTree("1 + 2 * 3",
        \\program
        \\    binary +
        \\        left: literal 1
        \\        right: binary *
        \\            left: literal 2
        \\            right: literal 3
        \\
    );
}

test "comparison does not chain" {
    try expectParsesToTree("a < b == c",
        \\program
        \\    binary ==
        \\        left: binary <
        \\            left: identifier a
        \\            right: identifier b
        \\        right: identifier c
        \\
    );
}

test "block as function argument" {
    try expectParsesToSource(
        \\f({
        \\    let x = 1;
        \\    x + 2
        \\})
    ,
        \\f({
        \\    let x = 1;
        \\    x + 2
        \\})
    );
}

test "function in list" {
    try expectParsesToSource(
        \\[(x) { x }, (y) { y * 2 }]
    ,
        \\[(x) { x }, (y) { y * 2 }]
    );
}

test "empty body function is error" {
    var parser = try Parser.init(testing.allocator, "() {}");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "unexpected token at top level is error" {
    var parser = try Parser.init(testing.allocator, "=>");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "unclosed paren is error" {
    var parser = try Parser.init(testing.allocator, "(1 + 2");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "unclosed bracket is error" {
    var parser = try Parser.init(testing.allocator, "[1, 2");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "unclosed brace is error" {
    var parser = try Parser.init(testing.allocator, "{ 1 + 2");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "let without value is error" {
    var parser = try Parser.init(testing.allocator, "let x;");
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "string literal" {
    try expectParsesToSource(
        \\"hello world"
    ,
        \\"hello world"
    );
}

test "boolean literals" {
    try expectParsesToSource("true", "true");
    try expectParsesToSource("false", "false");
}

test "float literal" {
    try expectParsesToSource("3.14", "3.14");
}

test "recursive pattern matching" {
    try expectParsesToSource(
        \\let len = (xs) {
        \\    [] => 0,
        \\    [_, ...rest] => 1 + len(rest)
        \\};
        \\len([1, 2, 3])
    ,
        \\let len = (xs) {
        \\    [] => 0,
        \\    [_, ...rest] => 1 + len(rest)
        \\};
        \\len([1, 2, 3])
    );
}

test "branch result with block" {
    try expectParsesToSource(
        \\(x) {
        \\    0 => {
        \\        let msg = "zero";
        \\        print(msg)
        \\    },
        \\    => x
        \\}
    ,
        \\(x) {
        \\    0 => {
        \\        let msg = "zero";
        \\        print(msg)
        \\    },
        \\    => x
        \\}
    );
}

test "complex expression as range bounds" {
    try expectParsesToSource("[f(1)..g(2)]", "[f(1)..g(2)]");
}

test "spread pattern at start of list" {
    try expectParsesToSource(
        \\(xs) {
        \\    [...rest] => rest
        \\}
    ,
        \\(xs) {
        \\    [...rest] => rest
        \\}
    );
}

test "empty list pattern" {
    try expectParsesToSource(
        \\(xs) {
        \\    [] => true,
        \\    _ => false
        \\}
    ,
        \\(xs) {
        \\    [] => true,
        \\    _ => false
        \\}
    );
}

test "parse all current examples" {
    const io = testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, "examples", .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".lx")) continue;

        const source = try dir.readFileAlloc(io, entry.name, testing.allocator, .limited(1024 * 1024));
        defer testing.allocator.free(source);

        var parser = try Parser.init(testing.allocator, source);
        defer parser.deinit();

        const node = try parser.parse();
        defer node.deinit(testing.allocator);
    }
}
