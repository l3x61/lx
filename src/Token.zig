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

    assign,
    fat_arrow,
    question,
    equal,
    not,
    not_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    lparen,
    rparen,
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    comma,
    semicolon,
    plus,
    concat,
    minus,
    star,
    slash,
    percent,
    and_and,
    or_or,
    spread,
    range,

    let,
    true,
    false,

    underscore,
    number,
    string,
    string_open,
    identifier,

    pub fn format(self: Tag, writer: anytype) !void {
        const name = switch (self) {
            .eof => "END OF FILE",
            .invalid => "INVALID",
            .comment => "COMMENT",
            .newline => "NEWLINE",

            .assign => "=",
            .fat_arrow => "=>",
            .question => "?",
            .equal => "==",
            .not => "!",
            .not_equal => "!=",
            .greater => ">",
            .greater_equal => ">=",
            .less => "<",
            .less_equal => "<=",
            .lparen => "(",
            .rparen => ")",
            .lbrace => "{",
            .rbrace => "}",
            .lbracket => "[",
            .rbracket => "]",
            .comma => ",",
            .semicolon => ";",
            .plus => "+",
            .concat => "++",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .percent => "%",
            .and_and => "&&",
            .or_or => "||",
            .spread => "...",
            .range => "..",

            .let => "let",
            .true => "true",
            .false => "false",

            .underscore => "_",
            .number => "NUMBER",
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

pub fn color(self: Token) []const u8 {
    const ansi = @import("ansi.zig");

    return switch (self.tag) {
        .let => ansi.red,

        .true,
        .false,
        => ansi.cyan,

        .number,
        .string,
        .string_open,
        => ansi.blue,

        .comment,
        .newline,
        => ansi.dim,

        .invalid => ansi.red,

        .assign,
        .fat_arrow,
        .question,
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
        .and_and,
        .or_or,
        .spread,
        .range,
        => ansi.yellow,

        else => ansi.reset,
    };
}
