const std = @import("std");
const Utf8View = std.unicode.Utf8View;
const Utf8Iterator = std.unicode.Utf8Iterator;
const print = std.debug.print;
const expect = std.testing.expect;
const expectError = std.testing.expectError;
const hexEscape = std.ascii.hexEscape;

const Token = @import("Token.zig");

const Lexer = @This();

const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "let", .let },
    .{ "match", .match },
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
        minus,
        amp,
        bar,
        colon,
        dot,
        number,
        string_double,
        string_single,
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
            '[' => {
                tag = .lbracket;
                break :state;
            },
            ']' => {
                tag = .rbracket;
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
            ',' => {
                tag = .comma;
                break :state;
            },
            ';' => {
                tag = .semicolon;
                break :state;
            },
            '\\' => {
                tag = .backslash;
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
                continue :state .minus;
            },
            '&' => {
                tag = .amp;
                continue :state .amp;
            },
            '|' => {
                tag = .bar;
                continue :state .bar;
            },
            ':' => {
                tag = .colon;
                continue :state .colon;
            },
            '.' => {
                tag = .dot;
                continue :state .dot;
            },
            '"' => {
                tag = .string;
                continue :state .string_double;
            },
            '\'' => {
                tag = .string;
                continue :state .string_single;
            },
            '0'...'9' => {
                tag = .integer;
                continue :state .number;
            },
            0x03BB => {
                tag = .lambda;
                break :state;
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

        .minus => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '>' => {
                    tag = .arrow;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .amp => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '&' => {
                    tag = .and_and;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .bar => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                '|' => {
                    tag = .or_or;
                    break :state;
                },
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .colon => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse break :state) {
                ':' => {
                    tag = .cons;
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
                    tag = .dot_dot;
                    break :state;
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
                else => {
                    iterator.i = previous;
                    break :state;
                },
            }
        },

        .string_double => {
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
                    continue :state .string_double;
                },
                '\n', '\r' => {
                    iterator.i = previous;
                    tag = .string_open;
                    break :state;
                },
                else => continue :state .string_double,
            }
        },

        .string_single => {
            const previous = iterator.i;
            switch (iterator.nextCodepoint() orelse {
                tag = .string_open;
                break :state;
            }) {
                '\'' => {
                    tag = .string;
                    break :state;
                },
                '\\' => {
                    _ = iterator.nextCodepoint() orelse {
                        tag = .string_open;
                        break :state;
                    };
                    continue :state .string_single;
                },
                '\n', '\r' => {
                    iterator.i = previous;
                    tag = .string_open;
                    break :state;
                },
                else => continue :state .string_single,
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
    return false;
}

fn isIdentifierContinueCodepoint(cp: u21) bool {
    if (cp == '_') return true;
    if (cp <= 0x7F) {
        const byte: u8 = @intCast(cp);
        return std.ascii.isAlphabetic(byte) or std.ascii.isDigit(byte);
    }
    return false;
}

fn runTest(input: []const u8, tokens: []const Token) !void {
    var lexer = try Lexer.init(input);

    const escaped = hexEscape(input, .upper);
    for (0.., tokens) |i, expected| {
        const actual = lexer.nextToken();

        expect(expected.equal(actual)) catch |err| {
            print("error: at token {d} of {d} in `{s}`\n", .{ i, tokens.len, escaped.data.bytes });
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
    const input = "let match answer _ _12x34 true false";
    const tokens = [_]Token{
        Token.init(.let, input, "let"),
        Token.init(.match, input, "match"),
        Token.init(.identifier, input, "answer"),
        Token.init(.underscore, input, "_"),
        Token.init(.identifier, input, "_12x34"),
        Token.init(.true, input, "true"),
        Token.init(.false, input, "false"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "lambda glyph" {
    const input = "λ x -> x";
    const tokens = [_]Token{
        Token.init(.lambda, input, "λ"),
        Token.init(.identifier, input, "x"),
        Token.init(.arrow, input, "->"),
        Token.init(.identifier, input, "x"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "punctuators" {
    const input = "\\ -> | & && || : :: . .. = ; , ( ) [ ] { }";
    const tokens = [_]Token{
        Token.init(.backslash, input, "\\"),
        Token.init(.arrow, input, "->"),
        Token.init(.bar, input, "|"),
        Token.init(.amp, input, "&"),
        Token.init(.and_and, input, "&&"),
        Token.init(.or_or, input, "||"),
        Token.init(.colon, input, ":"),
        Token.init(.cons, input, "::"),
        Token.init(.dot, input, "."),
        Token.init(.dot_dot, input, ".."),
        Token.init(.assign, input, "="),
        Token.init(.semicolon, input, ";"),
        Token.init(.comma, input, ","),
        Token.init(.lparen, input, "("),
        Token.init(.rparen, input, ")"),
        Token.init(.lbracket, input, "["),
        Token.init(.rbracket, input, "]"),
        Token.init(.lbrace, input, "{"),
        Token.init(.rbrace, input, "}"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "operators" {
    const input = "== != ! > >= < <= + ++ - * / %";
    const tokens = [_]Token{
        Token.init(.equal, input, "=="),
        Token.init(.not_equal, input, "!="),
        Token.init(.not, input, "!"),
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
        Token.init(.integer, input, "1"),
        Token.init(.newline, input, "\n"),
        Token.init(.comment, input, "# two"),
        Token.init(.newline, input, "\n"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "integer and dotdot" {
    const input = "0 42 [x, ..rest]";
    const tokens = [_]Token{
        Token.init(.integer, input, "0"),
        Token.init(.integer, input, "42"),
        Token.init(.lbracket, input, "["),
        Token.init(.identifier, input, "x"),
        Token.init(.comma, input, ","),
        Token.init(.dot_dot, input, ".."),
        Token.init(.identifier, input, "rest"),
        Token.init(.rbracket, input, "]"),
        Token.init(.eof, input, ""),
    };
    try runTest(input, &tokens);
}

test "double and single quoted strings" {
    {
        const input = "\"lx\"";
        const tokens = [_]Token{
            Token.init(.string, input, "\"lx\""),
            Token.init(.eof, input, ""),
        };
        try runTest(input, &tokens);
    }

    {
        const input = "'lx'";
        const tokens = [_]Token{
            Token.init(.string, input, "'lx'"),
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
