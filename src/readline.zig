const std = @import("std");
const Allocator = std.mem.Allocator;
const span = std.mem.span;

const C = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("readline/readline.h");
    @cInclude("readline/history.h");
});

pub fn readline(allocator: Allocator, prompt: []const u8) ![]u8 {
    const line = C.readline(prompt.ptr);
    if (line == null) {
        return allocator.dupe(u8, "");
    }

    defer C.free(line);
    if (line[0] != 0) {
        _ = C.add_history(line);
    }

    return allocator.dupe(u8, span(line));
}
