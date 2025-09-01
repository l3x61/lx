const std = @import("std");
const eql = std.mem.eql;
const FormatOptions = std.fmt.FormatOptions;

const Token = @This();

tag: Tag,
source: []const u8,
lexeme: []const u8,

pub const Tag = enum {
    eof,
    comment,

    lambda,
    dot,
    assign,
    equal,
    not_equal,
    lparen,
    rparen,

    plus,
    minus,
    star,
    slash,

    let,
    in,

    @"if",
    then,
    @"else",

    null,
    true,
    false,

    number,
    string,
    symbol,

    pub fn format(
        self: Tag,
        writer: anytype,
    ) !void {
        const name = switch (self) {
            .eof => "END OF FILE",
            .comment => "COMMENT",

            .lambda => "\\ or λ",
            .dot => ".",
            .assign => "=",
            .equal => "==",
            .not_equal => "!=",
            .lparen => "(",
            .rparen => ")",

            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",

            .let => "let",
            .in => "in",

            .@"if" => "if",
            .then => "then",
            .@"else" => "else",

            .null => "null",
            .true => "true",
            .false => "false",

            .number => "NUMBER",
            .string => "STRING",
            .symbol => "SYMBOL",
        };
        try writer.print("{s}", .{name});
    }
};

pub fn init(tag: Tag, source: []const u8, lexeme: []const u8) Token {
    return .{ .tag = tag, .source = source, .lexeme = lexeme };
}

pub fn equal(a: Token, b: Token) bool {
    return a.tag == b.tag and a.source.ptr == b.source.ptr and eql(u8, a.lexeme, b.lexeme);
}

pub fn format(self: Token, writer: anytype) !void {
    switch (self.tag) {
        .eof => try writer.print("end-of-file", .{}),
        else => try writer.print("{s}", .{self.lexeme}),
    }
}

// TODO: pretty print token shown in line

pub fn isOneOf(self: Token, expected: []const Tag) bool {
    for (expected) |tag| {
        if (self.tag == tag) {
            return true;
        }
    }
    return false;
}
