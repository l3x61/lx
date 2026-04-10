const std = @import("std");
const Utf8View = std.unicode.Utf8View;
const Utf8Iterator = std.unicode.Utf8Iterator;
const print = std.debug.print;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const hexEscape = std.ascii.hexEscape;

const ansi = @import("ansi.zig");
const Token = @import("Token.zig");

const Lexer = @This();

const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "let", .let },
    .{ "true", .true },
    .{ "false", .false },
});

source: []const u8,
iterator: Utf8Iterator,

pub fn init(source: []const u8) error{InvalidUtf8}!Lexer {
    var utf8_view = try Utf8View.init(source);
    return Lexer{
        .source = source,
        .iterator = utf8_view.iterator(),
    };
}

pub fn nextToken(self: *Lexer) Token {
    const source = self.source;
    const iterator = &self.iterator;

    const State = enum {
        start,
        newline,
        comment,
        equal,
        bang,
        greater,
        less,
        plus,
        dot,
        number,
        fraction,
        string,
        identifier,
    };

    var start = iterator.i;
    var tag: Token.Tag = .eof;

    state: switch (State.start) {
        .start => switch (iterator.nextCodepoint() orelse break :state) {
            ' ', '\t', '\x0B', '\x0C' => {
                start = iterator.i;
                continue :state .start;
            },
            '\n', '\r' => {
                tag = .newline;
                continue :state .newline;
            },
            '#' => {
                tag = .comment;
                continue :state .comment;
            },
            '(' => {
                tag = .lparen;
                break :state;
            },
            ')' => {
                tag = .rparen;
                break :state;
            },
            '{' => {
                tag = .lbrace;
                break :state;
            },
            '}' => {
                tag = .rbrace;
                break :state;
            },
            '[' => {
                tag = .lbracket;
                break :state;
            },
            ']' => {
                tag = .rbracket;
                break :state;
            },
            ',' => {
                tag = .comma;
                break :state;
            },
            ';' => {
                tag = .semicolon;
                break :state;
            },
            '?' => {
                tag = .question;
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
            '%' => {
                tag = .percent;
                break :state;
            },
            '=' => {
                tag = .assign;
                continue :state .equal;
            },
            '!' => {
                tag = .not;
                continue :state .bang;
            },
            '>' => {
                tag = .greater;
                continue :state .greater;
            },
            '<' => {
                tag = .less;
                continue :state .less;
            },
            '+' => {
                tag = .plus;
                continue :state .plus;
            },
            '-' => {
                tag = .minus;
                break :state;
            },
            '&' => {
                tag = .invalid;
                break :state;
            },
            '|' => {
                tag = .invalid;
                break :state;
            },
            '.' => {
                tag = .invalid;
                continue :state .dot;
            },
            '"' => {
                tag = .string;
                continue :state .string;
            },
            '0'...'9' => {
                tag = .number;
                continue :state .number;
            },
            else => |cp| {
                if (isIdentifierStartCodepoint(cp)) {
                    tag = .identifier;
                    continue :state .identifier;
                }

                tag = .invalid;
                break :state;
            },
        },

        .newline => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '\n', '\r' => continue :state .newline,
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .comment => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '\n', '\r' => {
                    iterator.i = previous;
                    break :state;
                },
                else => continue :state .comment,
            }
        },

        .equal => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '=' => {
                    tag = .equal;
                    break :state;
                },
                '>' => {
                    tag = .fat_arrow;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .bang => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '=' => {
                    tag = .not_equal;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .greater => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '=' => {
                    tag = .greater_equal;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .less => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '=' => {
                    tag = .less_equal;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .plus => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '+' => {
                    tag = .concat;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .dot => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '.' => {
                    const previous2 = iterator.i;
                    switch (iterator.nextCodepoint() orelse break :state) {
                        '.' => {
                            tag = .spread;
                            break :state;
                        },
                        else => {
                            iterator.i = previous2;
                            tag = .range;
                            break :state;
                        },
                    }
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .number => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '0'...'9' => continue :state .number,
                '.' => {
                    const fraction_previous = iterator.i;
                    switch (iterator.nextCodepoint() orelse {
                        iterator.i = previous;
                        break :state;
                    }) {
                        '0'...'9' => continue :state .fraction,
                        else => {
                            iterator.i = previous;
                            break :state;
                        },
                    }
                    iterator.i = fraction_previous;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .fraction => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '0'...'9' => continue :state .fraction,
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .string => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse {
                tag = .string_open;
                break :state;
            }) {
                '"' => {
                    tag = .string;
                    break :state;
                },
                '\\' => {
                    _ = iterator.nextCodepoint() orelse {
                        tag = .string_open;
                        break :state;
                    };
                    continue :state .string;
                },
                '\n', '\r' => {
                    iterator.i = previous;
                    tag = .string_open;
                    break :state;
                },
                else => continue :state .string,
            }
        },

        .identifier => {
            const previous = iterator.i;
            const cp = iterator.nextCodepoint() orelse break :state;
            if (isIdentifierContinueCodepoint(cp)) {
                continue :state .identifier;
            }

            iterator.i = previous;
            break :state;
        },
    }

    const lexeme = source[start..iterator.i];

    if (tag == .identifier) {
        if (std.mem.eql(u8, lexeme, "_")) return Token.init(.underscore, source, lexeme);
        if (keywords.get(lexeme)) |keyword| return Token.init(keyword, source, lexeme);
    }

    return Token.init(tag, source, lexeme);
}

fn isIdentifierStartCodepoint(cp: u21) bool {
    if (cp == '_') return true;
    if (cp <= 0x7F) return std.ascii.isAlphabetic(@intCast(cp));
    return true;
}

fn isIdentifierContinueCodepoint(cp: u21) bool {
    if (cp == '_') return true;
    if (cp <= 0x7F) {
        const byte: u8 = @intCast(cp);
        return std.ascii.isAlphabetic(byte) or std.ascii.isDigit(byte);
    }
    return true;
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

test "invalid utf8" {
    try expectError(error.InvalidUtf8, Lexer.init("\x80"));
}

test "keywords and identifiers" {
    const input = "let answer _ _12x34 true false";
    const tokens = [_]Token{
        Token.init(.let, input, "let"),
        Token.init(.identifier, input, "answer"),
        Token.init(.underscore, input, "_"),
        Token.init(.identifier, input, "_12x34"),
        Token.init(.true, input, "true"),
        Token.init(.false, input, "false"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "unicode identifier" {
    const input = "größe";
    const tokens = [_]Token{
        Token.init(.identifier, input, "größe"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "delimiters" {
    const input = "(){}[],;";
    const tokens = [_]Token{
        Token.init(.lparen, input, "("),
        Token.init(.rparen, input, ")"),
        Token.init(.lbrace, input, "{"),
        Token.init(.rbrace, input, "}"),
        Token.init(.lbracket, input, "["),
        Token.init(.rbracket, input, "]"),
        Token.init(.comma, input, ","),
        Token.init(.semicolon, input, ";"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "operators" {
    const input = "= => ? == ! != > >= < <= + ++ - * / % .. ...";
    const tokens = [_]Token{
        Token.init(.assign, input, "="),
        Token.init(.fat_arrow, input, "=>"),
        Token.init(.question, input, "?"),
        Token.init(.equal, input, "=="),
        Token.init(.not, input, "!"),
        Token.init(.not_equal, input, "!="),
        Token.init(.greater, input, ">"),
        Token.init(.greater_equal, input, ">="),
        Token.init(.less, input, "<"),
        Token.init(.less_equal, input, "<="),
        Token.init(.plus, input, "+"),
        Token.init(.concat, input, "++"),
        Token.init(.minus, input, "-"),
        Token.init(.star, input, "*"),
        Token.init(.slash, input, "/"),
        Token.init(.percent, input, "%"),
        Token.init(.range, input, ".."),
        Token.init(.spread, input, "..."),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "comments and newlines" {
    const input = "# one\r\nlet x = 1\n# two\n";
    const tokens = [_]Token{
        Token.init(.comment, input, "# one"),
        Token.init(.newline, input, "\r\n"),
        Token.init(.let, input, "let"),
        Token.init(.identifier, input, "x"),
        Token.init(.assign, input, "="),
        Token.init(.number, input, "1"),
        Token.init(.newline, input, "\n"),
        Token.init(.comment, input, "# two"),
        Token.init(.newline, input, "\n"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "numbers float and range" {
    const input = "1 3.14 [1..5] 1.";
    const tokens = [_]Token{
        Token.init(.number, input, "1"),
        Token.init(.number, input, "3.14"),
        Token.init(.lbracket, input, "["),
        Token.init(.number, input, "1"),
        Token.init(.range, input, ".."),
        Token.init(.number, input, "5"),
        Token.init(.rbracket, input, "]"),
        Token.init(.number, input, "1"),
        Token.init(.invalid, input, "."),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "string and unterminated string" {
    {
        const input = "\"lx\"";
        const tokens = [_]Token{
            Token.init(.string, input, "\"lx\""),
            Token.init(.eof, input, ""),
        };
        try runTest(input, &tokens);
    }

    {
        const input = "\"lx";
        const tokens = [_]Token{
            Token.init(.string_open, input, "\"lx"),
            Token.init(.eof, input, ""),
        };
        try runTest(input, &tokens);
    }
}

test "branch body example" {
    const input =
        \\let abs = (n) {
        \\    ? n >= 0 => n
        \\    => -n
        \\};
    ;

    const tokens = [_]Token{
        Token.init(.let, input, "let"),
        Token.init(.identifier, input, "abs"),
        Token.init(.assign, input, "="),
        Token.init(.lparen, input, "("),
        Token.init(.identifier, input, "n"),
        Token.init(.rparen, input, ")"),
        Token.init(.lbrace, input, "{"),
        Token.init(.newline, input, "\n"),
        Token.init(.question, input, "?"),
        Token.init(.identifier, input, "n"),
        Token.init(.greater_equal, input, ">="),
        Token.init(.number, input, "0"),
        Token.init(.fat_arrow, input, "=>"),
        Token.init(.identifier, input, "n"),
        Token.init(.newline, input, "\n"),
        Token.init(.fat_arrow, input, "=>"),
        Token.init(.minus, input, "-"),
        Token.init(.identifier, input, "n"),
        Token.init(.newline, input, "\n"),
        Token.init(.rbrace, input, "}"),
        Token.init(.semicolon, input, ";"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}
