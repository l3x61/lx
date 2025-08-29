const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.io.Reader;
const Writer = std.io.Writer;

const span = std.mem.span;

const C = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
});

pub fn readline(ator: Allocator, prompt: []const u8, in: *Reader, out: *Writer) ![]u8 {
    try out.writeAll(prompt);
    try out.flush();

    const line = try in.takeDelimiterInclusive('\n');
    return ator.dupe(u8, line);
}
