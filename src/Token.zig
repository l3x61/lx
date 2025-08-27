const std = @import("std");
const eql = std.mem.eql;
const FormatOptions = std.fmt.FormatOptions;

const Token = @This();

tag: Tag,
lexeme: []const u8,

pub const Tag = enum {
    eof,

    lambda,
    dot,
    equal,
    lparen,
    rparen,

    let,
    rec,
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
        comptime _: []const u8,
        _: FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{s}", .{@tagName(self)});
    }
};

pub fn init(tag: Tag, lexeme: []const u8) Token {
    return .{ .tag = tag, .lexeme = lexeme };
}

pub fn equal(a: Token, b: Token) bool {
    return a.tag == b.tag and eql(u8, a.lexeme, b.lexeme);
}

pub fn format(self: Token, comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
    switch (self.tag) {
        .eof => try writer.print("end-of-file", .{}),
        else => try writer.print("{s}", .{self.lexeme}),
    }
}

pub fn isOneOf(self: Token, expected: []const Tag) bool {
    for (expected) |tag| {
        if (self.tag == tag) {
            return true;
        }
    }
    return false;
}
