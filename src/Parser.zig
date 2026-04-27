const std = @import("std");
const Allocator = std.mem.Allocator;
const Terminal = std.Io.Terminal;
const testing = std.testing;
const fs = std.fs;

const Lexer = @import("Lexer.zig");
const node_mod = @import("node.zig");
const Node = node_mod.Node;
const Clause = node_mod.Clause;
const Pattern = node_mod.Pattern;
const Rest = node_mod.Rest;
const Token = @import("Token.zig");

const Parser = @This();

allocator: Allocator,
tokens: []Token,
index: usize,
source_name: []const u8,
last_error: ?Diagnostic,

pub const Diagnostic = struct {
    source_name: []const u8,
    token: Token,
    kind: Kind,

    const Kind = union(enum) {
        expected: Token.Tag,
        message: []const u8,
    };

    const Location = struct {
        line: usize,
        column: usize,
        line_text: []const u8,
        before_columns: usize,
        marker_width: usize,
    };

    pub fn write(self: Diagnostic, term: Terminal) !void {
        const writer = term.writer;
        const loc = self.location();

        try term.setColor(.bold);
        try term.setColor(.red);
        try writer.writeAll("Syntax error: ");
        try term.setColor(.reset);
        switch (self.kind) {
            .expected => |expected| {
                try writer.writeAll("expected \"");
                try expected.format(writer);
                try writer.writeAll("\" but got \"");
                try self.token.tag.format(writer);
                try writer.writeAll("\"\n");
            },
            .message => |message| {
                try writer.writeAll(message);
                try writer.writeByte('\n');
            },
        }

        try term.setColor(.dim);
        try writer.print("{s}:{d}:{d}\n", .{
            self.source_name,
            loc.line,
            loc.column,
        });
        try term.setColor(.reset);

        var line_buffer: [32]u8 = undefined;
        const line_number = try std.fmt.bufPrint(&line_buffer, "{d}", .{loc.line});

        try term.setColor(.dim);
        try writer.writeAll("  ");
        try writer.writeAll(line_number);
        try writer.writeAll(" | ");
        try term.setColor(.reset);
        try writeHighlightedLine(term, loc.line_text);
        try writer.writeByte('\n');

        try term.setColor(.dim);
        try writer.writeAll("  ");
        try writeRepeated(writer, ' ', line_number.len);
        try writer.writeAll(" | ");
        try term.setColor(.reset);
        try writeRepeated(writer, ' ', loc.before_columns);
        try term.setColor(.bold);
        try term.setColor(.red);
        try writeRepeated(writer, '^', loc.marker_width);
        try term.setColor(.reset);
        try writer.writeByte('\n');
    }

    fn location(self: Diagnostic) Location {
        const source = self.token.source;
        const start_index = self.token.startIndex();
        var cursor: usize = 0;
        var line_start: usize = 0;
        var line: usize = 1;

        while (cursor < start_index and cursor < source.len) : (cursor += 1) {
            if (source[cursor] == '\n') {
                line += 1;
                line_start = cursor + 1;
            }
        }

        var line_end = start_index;
        while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}

        const before = source[line_start..@min(start_index, source.len)];
        const token_end = @min(start_index + self.token.lexeme.len, line_end);
        const marker_slice = source[@min(start_index, source.len)..token_end];

        return .{
            .line = line,
            .column = utf8CountCodepoints(before) + 1,
            .line_text = source[line_start..line_end],
            .before_columns = utf8CountCodepoints(before),
            .marker_width = @max(1, utf8CountCodepoints(marker_slice)),
        };
    }
};

pub fn init(allocator: Allocator, source: []const u8) !Parser {
    return initNamed(allocator, "<input>", source);
}

pub fn initNamed(allocator: Allocator, source_name: []const u8, source: []const u8) !Parser {
    var lexer = try Lexer.init(source);
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);

    while (true) {
        const token = lexer.nextToken();
        if (token.tag != .comment and token.tag != .newline) try tokens.append(allocator, token);
        if (token.tag == .eof) break;
    }

    return .{
        .allocator = allocator,
        .tokens = try tokens.toOwnedSlice(allocator),
        .index = 0,
        .source_name = source_name,
        .last_error = null,
    };
}

pub fn deinit(self: *Parser) void {
    self.allocator.free(self.tokens);
}

pub fn parse(self: *Parser) !*Node {
    self.last_error = null;
    const expression = try self.parseExpression();
    errdefer expression.deinit(self.allocator);
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
    if (token.tag != tag) return self.failExpected(tag);
    return self.advance();
}

fn match(self: *Parser, tag: Token.Tag) bool {
    if (self.current().tag != tag) return false;
    _ = self.advance();
    return true;
}

fn failExpected(self: *Parser, expected: Token.Tag) error{SyntaxError} {
    self.last_error = .{
        .source_name = self.source_name,
        .token = self.current(),
        .kind = .{ .expected = expected },
    };
    return error.SyntaxError;
}

fn failMessage(self: *Parser, message: []const u8) error{SyntaxError} {
    self.last_error = .{
        .source_name = self.source_name,
        .token = self.current(),
        .kind = .{ .message = message },
    };
    return error.SyntaxError;
}

fn parseExpression(self: *Parser) anyerror!*Node {
    return self.parseBind();
}

fn parseBind(self: *Parser) anyerror!*Node {
    if (self.current().tag != .let) return self.parseMatch();

    _ = self.advance();
    const pattern = try self.parseBindOrHeadPattern();
    errdefer pattern.deinit(self.allocator);

    _ = try self.expect(.assign);
    const value = try self.parseExpression();
    errdefer value.deinit(self.allocator);

    _ = try self.expect(.semicolon);
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

fn parseMatch(self: *Parser) anyerror!*Node {
    if (self.current().tag != .match) return self.parseLogicOr();

    _ = self.advance();
    const subject = try self.parseLogicOr();
    errdefer subject.deinit(self.allocator);

    if (self.current().tag != .backslash and self.current().tag != .lambda) {
        return self.failMessage("expected function abstraction after match subject");
    }

    const function = try self.parseFunction();
    errdefer function.deinit(self.allocator);

    return Node.create(self.allocator, .{
        .application = .{
            .callee = function,
            .argument = subject,
        },
    });
}

fn parseLogicOr(self: *Parser) anyerror!*Node {
    var left = try self.parseLogicAnd();
    errdefer left.deinit(self.allocator);

    while (self.current().tag == .or_or) {
        const operator = self.advance();
        left = blk: {
            const right = try self.parseLogicAnd();
            errdefer right.deinit(self.allocator);
            break :blk try Node.create(self.allocator, .{
                .binary = .{ .left = left, .operator = operator, .right = right },
            });
        };
    }
    return left;
}

fn parseLogicAnd(self: *Parser) anyerror!*Node {
    var left = try self.parseEquality();
    errdefer left.deinit(self.allocator);

    while (self.current().tag == .and_and) {
        const operator = self.advance();
        left = blk: {
            const right = try self.parseEquality();
            errdefer right.deinit(self.allocator);
            break :blk try Node.create(self.allocator, .{
                .binary = .{ .left = left, .operator = operator, .right = right },
            });
        };
    }
    return left;
}

fn parseEquality(self: *Parser) anyerror!*Node {
    const left = try self.parseComparison();
    errdefer left.deinit(self.allocator);

    switch (self.current().tag) {
        .equal, .not_equal => {
            const operator = self.advance();
            const right = try self.parseComparison();
            errdefer right.deinit(self.allocator);
            return Node.create(self.allocator, .{
                .binary = .{ .left = left, .operator = operator, .right = right },
            });
        },
        else => return left,
    }
}

fn parseComparison(self: *Parser) anyerror!*Node {
    const left = try self.parseConcat();
    errdefer left.deinit(self.allocator);

    switch (self.current().tag) {
        .less, .less_equal, .greater, .greater_equal => {
            const operator = self.advance();
            const right = try self.parseConcat();
            errdefer right.deinit(self.allocator);
            return Node.create(self.allocator, .{
                .binary = .{ .left = left, .operator = operator, .right = right },
            });
        },
        else => return left,
    }
}

fn parseConcat(self: *Parser) anyerror!*Node {
    var left = try self.parseCons();
    errdefer left.deinit(self.allocator);

    while (self.current().tag == .concat) {
        const operator = self.advance();
        left = blk: {
            const right = try self.parseCons();
            errdefer right.deinit(self.allocator);
            break :blk try Node.create(self.allocator, .{
                .binary = .{ .left = left, .operator = operator, .right = right },
            });
        };
    }
    return left;
}

fn parseCons(self: *Parser) anyerror!*Node {
    const left = try self.parseAdditive();
    errdefer left.deinit(self.allocator);

    if (self.current().tag == .cons) {
        const operator = self.advance();
        const right = try self.parseCons();
        errdefer right.deinit(self.allocator);
        return Node.create(self.allocator, .{
            .binary = .{ .left = left, .operator = operator, .right = right },
        });
    }
    return left;
}

fn parseAdditive(self: *Parser) anyerror!*Node {
    var left = try self.parseMultiplicative();
    errdefer left.deinit(self.allocator);

    while (true) {
        switch (self.current().tag) {
            .plus, .minus => {
                const operator = self.advance();
                left = blk: {
                    const right = try self.parseMultiplicative();
                    errdefer right.deinit(self.allocator);
                    break :blk try Node.create(self.allocator, .{
                        .binary = .{ .left = left, .operator = operator, .right = right },
                    });
                };
            },
            else => return left,
        }
    }
}

fn parseMultiplicative(self: *Parser) anyerror!*Node {
    var left = try self.parsePrefix();
    errdefer left.deinit(self.allocator);

    while (true) {
        switch (self.current().tag) {
            .star, .slash, .percent => {
                const operator = self.advance();
                left = blk: {
                    const right = try self.parsePrefix();
                    errdefer right.deinit(self.allocator);
                    break :blk try Node.create(self.allocator, .{
                        .binary = .{ .left = left, .operator = operator, .right = right },
                    });
                };
            },
            else => return left,
        }
    }
}

fn parsePrefix(self: *Parser) anyerror!*Node {
    switch (self.current().tag) {
        .minus, .not => {
            const operator = self.advance();
            const operand = try self.parsePrefix();
            errdefer operand.deinit(self.allocator);
            return Node.create(self.allocator, .{
                .unary = .{ .operator = operator, .operand = operand },
            });
        },
        else => return self.parsePostfix(),
    }
}

fn parsePostfix(self: *Parser) anyerror!*Node {
    var base = try self.parsePrimary();
    errdefer base.deinit(self.allocator);

    while (true) {
        switch (self.current().tag) {
            .lparen => {
                base = try self.parseCallSuffix(base);
            },
            .lbracket => {
                _ = self.advance();
                const idx = try self.parseExpression();
                errdefer idx.deinit(self.allocator);
                _ = try self.expect(.rbracket);
                base = blk: {
                    break :blk try Node.create(self.allocator, .{
                        .index = .{ .target = base, .index = idx },
                    });
                };
            },
            .dot => {
                _ = self.advance();
                const field = try self.expect(.identifier);
                const idx = try Node.create(self.allocator, .{
                    .literal = Token.init(.string, field.source, field.lexeme),
                });
                errdefer idx.deinit(self.allocator);
                base = blk: {
                    break :blk try Node.create(self.allocator, .{
                        .index = .{ .target = base, .index = idx },
                    });
                };
            },
            else => break,
        }
    }
    return base;
}

fn parseCallSuffix(self: *Parser, callee: *Node) anyerror!*Node {
    const open = try self.expect(.lparen);

    if (self.current().tag == .rparen) {
        const close = self.advance();
        const unit_node = try Node.create(self.allocator, .{
            .literal = unitToken(open, close),
        });
        errdefer unit_node.deinit(self.allocator);
        return Node.create(self.allocator, .{
            .application = .{ .callee = callee, .argument = unit_node },
        });
    }

    var args: std.ArrayList(*Node) = .empty;
    defer args.deinit(self.allocator);
    errdefer for (args.items) |arg| arg.deinit(self.allocator);

    try args.append(self.allocator, try self.parseExpression());
    while (self.match(.comma)) {
        try args.append(self.allocator, try self.parseExpression());
    }
    _ = try self.expect(.rparen);

    if (args.items.len == 1) {
        return Node.create(self.allocator, .{
            .application = .{ .callee = callee, .argument = args.items[0] },
        });
    }

    const owned = try self.allocator.dupe(*Node, args.items);
    errdefer self.allocator.free(owned);

    const tuple_node = try Node.create(self.allocator, .{
        .tuple = .{ .items = owned },
    });
    errdefer tuple_node.deinit(self.allocator);

    return Node.create(self.allocator, .{
        .application = .{ .callee = callee, .argument = tuple_node },
    });
}

fn parsePrimary(self: *Parser) anyerror!*Node {
    const token = self.current();
    return switch (token.tag) {
        .identifier => blk: {
            _ = self.advance();
            break :blk try Node.create(self.allocator, .{ .identifier = token });
        },
        .integer, .string, .true, .false => blk: {
            _ = self.advance();
            break :blk try Node.create(self.allocator, .{ .literal = token });
        },
        .lparen => self.parseParenOrTupleOrUnit(),
        .lbracket => self.parseList(),
        .lbrace => self.parseMap(),
        .backslash, .lambda => self.parseFunction(),
        else => self.failMessage("expected expression"),
    };
}

fn parseParenOrTupleOrUnit(self: *Parser) anyerror!*Node {
    const open = try self.expect(.lparen);

    if (self.current().tag == .rparen) {
        const close = self.advance();
        return Node.create(self.allocator, .{ .literal = unitToken(open, close) });
    }

    const first = try self.parseExpression();
    errdefer first.deinit(self.allocator);

    if (self.match(.comma)) {
        var items: std.ArrayList(*Node) = .empty;
        errdefer {
            for (items.items) |item| item.deinit(self.allocator);
            items.deinit(self.allocator);
        }
        try items.append(self.allocator, first);

        while (true) {
            try items.append(self.allocator, try self.parseExpression());
            if (!self.match(.comma)) break;
        }

        _ = try self.expect(.rparen);
        const owned = try items.toOwnedSlice(self.allocator);
        return Node.create(self.allocator, .{ .tuple = .{ .items = owned } });
    }

    _ = try self.expect(.rparen);
    return first;
}

fn unitToken(open: Token, close: Token) Token {
    const start = open.startIndex();
    const end = close.startIndex() + close.lexeme.len;
    return Token.init(.unit, open.source, open.source[start..end]);
}

fn parseList(self: *Parser) anyerror!*Node {
    _ = try self.expect(.lbracket);

    var items: std.ArrayList(*Node) = .empty;
    errdefer {
        for (items.items) |item| item.deinit(self.allocator);
        items.deinit(self.allocator);
    }

    if (self.current().tag != .rbracket) {
        try items.append(self.allocator, try self.parseExpression());
        while (self.match(.comma)) {
            try items.append(self.allocator, try self.parseExpression());
        }
    }

    _ = try self.expect(.rbracket);
    const owned = try items.toOwnedSlice(self.allocator);
    return Node.create(self.allocator, .{ .list = .{ .items = owned } });
}

fn parseMap(self: *Parser) anyerror!*Node {
    _ = try self.expect(.lbrace);

    var entries: std.ArrayList(Node.Map.Entry) = .empty;
    errdefer {
        for (entries.items) |entry| {
            self.allocator.free(entry.key);
            entry.value.deinit(self.allocator);
        }
        entries.deinit(self.allocator);
    }

    if (self.current().tag != .rbrace) {
        while (true) {
            const key = try self.parseRecordKey();
            var key_transferred = false;
            errdefer if (!key_transferred) self.allocator.free(key);

            _ = try self.expect(.colon);

            const value = try self.parseExpression();
            errdefer value.deinit(self.allocator);

            try entries.append(self.allocator, .{ .key = key, .value = value });
            key_transferred = true;
            if (!self.match(.comma)) break;
        }
    }

    _ = try self.expect(.rbrace);
    const owned = try entries.toOwnedSlice(self.allocator);
    return Node.create(self.allocator, .{ .map = .{ .entries = owned } });
}

fn parseRecordKey(self: *Parser) anyerror![]const u8 {
    const token = self.current();
    switch (token.tag) {
        .identifier => {
            _ = self.advance();
            return self.allocator.dupe(u8, token.lexeme);
        },
        .string => {
            _ = self.advance();
            return decodeStaticStringLiteral(self.allocator, token.lexeme) catch |err| switch (err) {
                error.InvalidStringLiteral => self.failMessage("invalid record key string"),
                else => return err,
            };
        },
        else => return self.failMessage("expected record key"),
    }
}

fn parseFunction(self: *Parser) anyerror!*Node {
    const intro = self.current();
    if (intro.tag != .backslash and intro.tag != .lambda) {
        return self.failMessage("expected \\ or λ");
    }
    _ = self.advance();

    var clauses: std.ArrayList(*Clause) = .empty;
    errdefer {
        for (clauses.items) |clause| clause.deinit(self.allocator);
        clauses.deinit(self.allocator);
    }

    try clauses.append(self.allocator, try self.parseClause());
    while (self.current().tag == .bar) {
        _ = self.advance();
        try clauses.append(self.allocator, try self.parseClause());
    }

    const owned = try clauses.toOwnedSlice(self.allocator);
    return Node.create(self.allocator, .{ .function = .{ .clauses = owned } });
}

fn parseClause(self: *Parser) anyerror!*Clause {
    const pattern = try self.parseBindOrHeadPattern();
    errdefer pattern.deinit(self.allocator);

    _ = try self.expect(.arrow);
    const body = try self.parseExpression();
    errdefer body.deinit(self.allocator);

    return Clause.create(self.allocator, pattern, body);
}

fn parseBindOrHeadPattern(self: *Parser) anyerror!*Pattern {
    const first = try self.parsePattern();
    errdefer first.deinit(self.allocator);

    if (self.current().tag != .comma) return first;

    var items: std.ArrayList(*Pattern) = .empty;
    errdefer {
        for (items.items) |item| item.deinit(self.allocator);
        items.deinit(self.allocator);
    }
    try items.append(self.allocator, first);

    while (self.match(.comma)) {
        try items.append(self.allocator, try self.parsePattern());
    }

    const owned = try items.toOwnedSlice(self.allocator);
    return Pattern.create(self.allocator, .{ .tuple = .{ .items = owned } });
}

fn parsePattern(self: *Parser) anyerror!*Pattern {
    return self.parseAlternativePattern();
}

fn parseAlternativePattern(self: *Parser) anyerror!*Pattern {
    var left = try self.parseRefinementPattern();
    errdefer left.deinit(self.allocator);

    while (self.current().tag == .bar) {
        _ = self.advance();
        left = blk: {
            const right = try self.parseRefinementPattern();
            errdefer right.deinit(self.allocator);
            break :blk try Pattern.create(self.allocator, .{
                .alternative = .{ .left = left, .right = right },
            });
        };
    }
    return left;
}

fn parseRefinementPattern(self: *Parser) anyerror!*Pattern {
    var base = try self.parseAtomicPattern();
    errdefer base.deinit(self.allocator);

    while (self.current().tag == .amp) {
        _ = self.advance();
        base = blk: {
            const cond = try self.parseExpression();
            errdefer cond.deinit(self.allocator);
            break :blk try Pattern.create(self.allocator, .{
                .refinement = .{ .base = base, .condition = cond },
            });
        };
    }
    return base;
}

fn parseAtomicPattern(self: *Parser) anyerror!*Pattern {
    const token = self.current();
    switch (token.tag) {
        .underscore => {
            _ = self.advance();
            return Pattern.create(self.allocator, .{ .wildcard = {} });
        },
        .identifier => {
            _ = self.advance();
            return Pattern.create(self.allocator, .{ .identifier = token });
        },
        .true, .false, .integer, .string => {
            _ = self.advance();
            return Pattern.create(self.allocator, .{
                .literal = .{ .token = token, .negate = false },
            });
        },
        .minus => {
            _ = self.advance();
            const next = self.current();
            if (next.tag != .integer) return self.failMessage("expected integer after - in pattern");
            _ = self.advance();
            return Pattern.create(self.allocator, .{
                .literal = .{ .token = next, .negate = true },
            });
        },
        .lparen => return self.parseParenPattern(),
        .lbracket => return self.parseListPattern(),
        .lbrace => return self.parseMapPattern(),
        else => return self.failMessage("expected pattern"),
    }
}

fn parseParenPattern(self: *Parser) anyerror!*Pattern {
    const open = try self.expect(.lparen);
    if (self.match(.rparen)) {
        return Pattern.create(self.allocator, .{
            .literal = .{ .token = Token.init(.unit, open.source, open.lexeme), .negate = false },
        });
    }

    const first = try self.parsePattern();
    errdefer first.deinit(self.allocator);

    if (self.match(.comma)) {
        var items: std.ArrayList(*Pattern) = .empty;
        errdefer {
            for (items.items) |item| item.deinit(self.allocator);
            items.deinit(self.allocator);
        }
        try items.append(self.allocator, first);

        while (true) {
            try items.append(self.allocator, try self.parsePattern());
            if (!self.match(.comma)) break;
        }

        _ = try self.expect(.rparen);
        const owned = try items.toOwnedSlice(self.allocator);
        return Pattern.create(self.allocator, .{ .tuple = .{ .items = owned } });
    }

    _ = try self.expect(.rparen);
    return first;
}

fn parseListPattern(self: *Parser) anyerror!*Pattern {
    _ = try self.expect(.lbracket);

    var items: std.ArrayList(*Pattern) = .empty;
    errdefer {
        for (items.items) |item| item.deinit(self.allocator);
        items.deinit(self.allocator);
    }
    var rest: Rest = .none;
    errdefer switch (rest) {
        .pattern => |p| p.deinit(self.allocator),
        else => {},
    };

    if (self.current().tag == .rbracket) {
        _ = self.advance();
        const owned = try items.toOwnedSlice(self.allocator);
        return Pattern.create(self.allocator, .{
            .list = .{ .items = owned, .rest = .none },
        });
    }

    if (self.current().tag == .dot_dot) {
        _ = self.advance();
        rest = try self.parseRestBinder();
    } else {
        try items.append(self.allocator, try self.parsePattern());
        while (self.match(.comma)) {
            if (self.current().tag == .dot_dot) {
                _ = self.advance();
                rest = try self.parseRestBinder();
                break;
            }
            try items.append(self.allocator, try self.parsePattern());
        }
    }

    _ = try self.expect(.rbracket);
    const owned = try items.toOwnedSlice(self.allocator);
    return Pattern.create(self.allocator, .{
        .list = .{ .items = owned, .rest = rest },
    });
}

fn parseMapPattern(self: *Parser) anyerror!*Pattern {
    _ = try self.expect(.lbrace);

    var entries: std.ArrayList(Pattern.MapPattern.Entry) = .empty;
    errdefer {
        for (entries.items) |entry| {
            self.allocator.free(entry.key);
            entry.pattern.deinit(self.allocator);
        }
        entries.deinit(self.allocator);
    }
    var rest: Rest = .none;
    errdefer switch (rest) {
        .pattern => |p| p.deinit(self.allocator),
        else => {},
    };

    if (self.current().tag != .rbrace) {
        if (self.current().tag == .dot_dot) {
            _ = self.advance();
            rest = try self.parseRestBinder();
        } else {
            while (true) {
                const key = try self.parseMapPatternKey();
                var key_transferred = false;
                var value_pattern: ?*Pattern = null;
                errdefer if (!key_transferred) {
                    self.allocator.free(key);
                    if (value_pattern) |p| p.deinit(self.allocator);
                };

                if (mapPatternHasKey(entries.items, key)) {
                    return self.failMessage("duplicate record pattern key");
                }

                _ = try self.expect(.colon);
                value_pattern = try self.parsePattern();

                try entries.append(self.allocator, .{ .key = key, .pattern = value_pattern.? });
                key_transferred = true;

                if (!self.match(.comma)) break;
                if (self.current().tag == .dot_dot) {
                    _ = self.advance();
                    rest = try self.parseRestBinder();
                    break;
                }
            }
        }
    }

    _ = try self.expect(.rbrace);
    const owned = try entries.toOwnedSlice(self.allocator);
    return Pattern.create(self.allocator, .{
        .map = .{ .entries = owned, .rest = rest },
    });
}

fn parseMapPatternKey(self: *Parser) anyerror![]const u8 {
    const token = self.current();
    switch (token.tag) {
        .identifier => {
            _ = self.advance();
            return self.allocator.dupe(u8, token.lexeme);
        },
        .string => {
            _ = self.advance();
            return decodeStaticStringLiteral(self.allocator, token.lexeme) catch |err| switch (err) {
                error.InvalidStringLiteral => self.failMessage("invalid record pattern key string"),
                else => return err,
            };
        },
        else => return self.failMessage("expected record pattern key"),
    }
}

fn mapPatternHasKey(entries: []const Pattern.MapPattern.Entry, key: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return true;
    }
    return false;
}

fn parseRestBinder(self: *Parser) anyerror!Rest {
    if (!isPatternStart(self.current().tag)) return .wildcard;
    const p = try self.parsePattern();
    return .{ .pattern = p };
}

fn isPatternStart(tag: Token.Tag) bool {
    return switch (tag) {
        .underscore, .identifier, .integer, .string, .true, .false, .lparen, .lbracket, .lbrace, .minus => true,
        else => false,
    };
}

fn decodeStaticStringLiteral(gpa: Allocator, lexeme: []const u8) anyerror![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(gpa);

    var index: usize = 1;
    while (index + 1 < lexeme.len) {
        const byte = lexeme[index];
        if (byte == '\\') {
            index += 1;
            if (index + 1 > lexeme.len) return error.InvalidStringLiteral;
            const escaped = lexeme[index];
            try buffer.append(gpa, switch (escaped) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                else => return error.InvalidStringLiteral,
            });
        } else {
            try buffer.append(gpa, byte);
        }
        index += 1;
    }

    return buffer.toOwnedSlice(gpa);
}

fn utf8CountCodepoints(bytes: []const u8) usize {
    var count: usize = 0;
    for (bytes) |byte| {
        if ((byte & 0xC0) != 0x80) count += 1;
    }
    return count;
}

fn writeRepeated(writer: anytype, byte: u8, count: usize) !void {
    for (0..count) |_| try writer.writeByte(byte);
}

fn writeHighlightedLine(term: Terminal, source: []const u8) !void {
    var lexer = try Lexer.init(source);
    var previous_index: usize = 0;

    while (true) {
        const token = lexer.nextToken();
        if (token.tag == .eof) break;

        const token_index = token.startIndex();
        if (token_index > previous_index) {
            try term.writer.writeAll(source[previous_index..token_index]);
        }

        try term.setColor(token.color());
        try term.writer.writeAll(token.lexeme);
        try term.setColor(.reset);

        previous_index = token_index + token.lexeme.len;
    }

    if (previous_index < source.len) {
        try term.writer.writeAll(source[previous_index..]);
    }
}

fn expectParses(input: []const u8) !void {
    var parser = try Parser.init(testing.allocator, input);
    defer parser.deinit();
    const node = try parser.parse();
    defer node.deinit(testing.allocator);
}

fn expectSyntaxError(input: []const u8) !void {
    var parser = try Parser.init(testing.allocator, input);
    defer parser.deinit();
    try testing.expectError(error.SyntaxError, parser.parse());
}

test "literal program" {
    try expectParses("42");
}

test "unit literal" {
    try expectParses("()");
}

test "unit literal keeps full lexeme" {
    var parser = try Parser.init(testing.allocator, "()");
    defer parser.deinit();
    const node = try parser.parse();
    defer node.deinit(testing.allocator);

    const expression = switch (node.*) {
        .program => |program| program.expression,
        else => return error.TestExpectedProgram,
    };
    const token = switch (expression.*) {
        .literal => |literal| literal,
        else => return error.TestExpectedLiteral,
    };

    try testing.expectEqual(.unit, token.tag);
    try testing.expectEqualStrings("()", token.lexeme);
}

test "zero argument call keeps full unit lexeme" {
    var parser = try Parser.init(testing.allocator, "f()");
    defer parser.deinit();
    const node = try parser.parse();
    defer node.deinit(testing.allocator);

    const expression = switch (node.*) {
        .program => |program| program.expression,
        else => return error.TestExpectedProgram,
    };
    const app = switch (expression.*) {
        .application => |application| application,
        else => return error.TestExpectedApplication,
    };
    const token = switch (app.argument.*) {
        .literal => |literal| literal,
        else => return error.TestExpectedLiteral,
    };

    try testing.expectEqual(.unit, token.tag);
    try testing.expectEqualStrings("()", token.lexeme);
}

test "binding" {
    try expectParses("let x = 1; x");
}

test "lambda" {
    try expectParses("\\ x -> x + 1");
}

test "lambda glyph" {
    try expectParses("λ x -> x + 1");
}

test "multi-clause function" {
    try expectParses("\\ 0 -> 1 | n -> n");
}

test "match expression" {
    try expectParses("match xs \\ [] -> 0 | [x, ..] -> x");
}

test "call zero arguments" {
    try expectParses("f()");
}

test "call one argument" {
    try expectParses("f(x)");
}

test "call multi argument" {
    try expectParses("add(1, 2)");
}

test "tuple pattern sugar" {
    try expectParses("\\ x, y -> x + y");
}

test "refinement pattern" {
    try expectParses("\\ x & x > 0 -> x");
}

test "alternative pattern" {
    try expectParses("\\ 0 | 1 -> true | _ -> false");
}

test "list cons" {
    try expectParses("1 :: 2 :: []");
}

test "list rest sugar" {
    try expectParses("\\ [x, ..] -> x");
}

test "list rest binder" {
    try expectParses("\\ [x, ..xs] -> xs");
}

test "record patterns" {
    try expectParses("\\ {} -> 0");
    try expectParses("\\ {name: n} -> n");
    try expectParses("\\ {\"name\": n, ..} -> n");
    try expectParses("\\ {name: n, ..rest} -> rest");
}

test "record pattern duplicate keys" {
    try expectSyntaxError("\\ {name: x, \"name\": y} -> x");
}

test "record literals" {
    try expectParses("{}");
    try expectParses("{\"a\": 1, \"b\": 2}");
    try expectParses("{a: 1, b: 2}");
    try expectSyntaxError("{(1, 2): [3, 4]}");
}

test "indexing" {
    try expectParses("xs[0]");
}

test "member access" {
    try expectParses("m.name");
    try expectParses("m.user.name");
    try expectParses("f().name");
    try expectParses("m.items[0].name");
}

test "nested indexing" {
    try expectParses("xs[0][1]");
}

test "negative integer pattern" {
    try expectParses("\\ -1 -> true | _ -> false");
}

test "destructuring binding" {
    try expectParses("let x, y = (1, 2); x + y");
}

test "call then index" {
    try expectParses("f(x)[0]");
}

test "index then call" {
    try expectParses("f[0](x)");
}
