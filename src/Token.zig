const std = @import("std");
const eql = std.mem.eql;

const Token = @This();

tag: Tag,
source: []const u8,
lexeme: []const u8,

pub const Tag = enum {
    eof,
    invalid,
    comment,
    newline,

    backslash,
    lambda,
    arrow,
    bar,
    amp,
    and_and,
    or_or,
    cons,
    dot,
    dot_dot,
    assign,
    semicolon,
    comma,
    colon,

    equal,
    not_equal,
    not,
    greater,
    greater_equal,
    less,
    less_equal,

    plus,
    minus,
    star,
    slash,
    percent,
    concat,

    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,

    let,
    match,
    true,
    false,

    underscore,
    unit,
    integer,
    string,
    string_open,
    identifier,

    pub fn format(self: Tag, writer: anytype) !void {
        const name = switch (self) {
            .eof => "END OF FILE",
            .invalid => "INVALID",
            .comment => "COMMENT",
            .newline => "NEWLINE",

            .backslash => "\\",
            .lambda => "λ",
            .arrow => "->",
            .bar => "|",
            .amp => "&",
            .and_and => "&&",
            .or_or => "||",
            .cons => "::",
            .dot => ".",
            .dot_dot => "..",
            .assign => "=",
            .semicolon => ";",
            .comma => ",",
            .colon => ":",

            .equal => "==",
            .not_equal => "!=",
            .not => "!",
            .greater => ">",
            .greater_equal => ">=",
            .less => "<",
            .less_equal => "<=",

            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .percent => "%",
            .concat => "++",

            .lparen => "(",
            .rparen => ")",
            .lbracket => "[",
            .rbracket => "]",
            .lbrace => "{",
            .rbrace => "}",

            .let => "let",
            .match => "match",
            .true => "true",
            .false => "false",

            .underscore => "_",
            .unit => "()",
            .integer => "INTEGER",
            .string => "STRING",
            .string_open => "OPEN STRING",
            .identifier => "IDENTIFIER",
        };
        try writer.print("{s}", .{name});
    }
};

pub fn init(tag: Tag, source: []const u8, lexeme: []const u8) Token {
    return .{ .tag = tag, .source = source, .lexeme = lexeme };
}

pub fn equal(a: Token, b: Token) bool {
    return a.tag == b.tag and eql(u8, a.lexeme, b.lexeme);
}

pub fn startIndex(self: Token) usize {
    return @intFromPtr(self.lexeme.ptr) - @intFromPtr(self.source.ptr);
}

pub fn format(self: Token, writer: anytype) !void {
    switch (self.tag) {
        .eof => try writer.print("end-of-file", .{}),
        else => try writer.print("{s}", .{self.lexeme}),
    }
}

pub fn isOneOf(self: Token, expected: []const Tag) bool {
    for (expected) |tag| {
        if (self.tag == tag) return true;
    }
    return false;
}

pub fn color(self: Token) std.Io.Terminal.Color {
    return switch (self.tag) {
        .let, .match => .red,
        .backslash, .lambda => .red,

        .true,
        .false,
        => .cyan,

        .integer,
        .string,
        .string_open,
        => .blue,

        .comment,
        .newline,
        => .dim,

        .invalid => .red,

        .arrow,
        .bar,
        .amp,
        .and_and,
        .or_or,
        .cons,
        .dot,
        .dot_dot,
        .assign,
        .colon,
        .equal,
        .not,
        .not_equal,
        .greater,
        .greater_equal,
        .less,
        .less_equal,
        .plus,
        .concat,
        .minus,
        .star,
        .slash,
        .percent,
        => .yellow,

        else => .reset,
    };
}
