const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const max_path_bytes = std.fs.max_path_bytes;

const ansi = @import("ansi.zig");
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const ReadLine = @import("readline.zig");
const Runtime = @import("Runtime.zig");
const Token = @import("Token.zig");

const Repl = @This();
const prompt = ansi.cyan ++ "> " ++ ansi.reset;
const continuation_prompt = ansi.dim ++ "| " ++ ansi.reset;

pub const AstMode = enum {
    off,
    tree,
    source,

    pub fn next(self: AstMode) AstMode {
        return switch (self) {
            .off => .tree,
            .tree => .source,
            .source => .off,
        };
    }

    pub fn label(self: AstMode) []const u8 {
        return switch (self) {
            .off => "off",
            .tree => "tree",
            .source => "source",
        };
    }
};

gpa: Allocator,
rl: ReadLine,
ast_mode: AstMode,
runtime: Runtime,

var stdout_buffer: [max_path_bytes]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var stderr_buffer: [max_path_bytes]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
const stderr = &stderr_writer.interface;

pub fn init(gpa: Allocator) !Repl {
    return .{
        .gpa = gpa,
        .rl = ReadLine.init(gpa, stdout),
        .ast_mode = .off,
        .runtime = try Runtime.init(gpa),
    };
}

pub fn deinit(self: *Repl) void {
    self.runtime.deinit();
    self.rl.deinit();
}

pub fn run(self: *Repl) !void {
    try welcomeMessage();

    while (true) {
        const line = self.readInput() catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };
        defer self.gpa.free(line);

        const handled = self.handleCommand(line) catch |err| {
            try stderr.print("{t}\n", .{err});
            try stderr.flush();
            continue;
        };
        if (handled) continue;

        self.renderLine(stdout, line) catch |err| {
            try stderr.print("{t}\n", .{err});
            try stderr.flush();
            continue;
        };
    }
}

fn renderLine(self: *Repl, out: anytype, source: []const u8) !void {
    if (self.ast_mode == .off) {
        const value = try self.runtime.evaluateSource(source);
        switch (value) {
            .unit => {},
            else => {
                try value.write(out);
                try out.writeByte('\n');
                try out.flush();
            },
        }
        return;
    }

    try render(out, self.gpa, source, self.ast_mode);
    try out.writeByte('\n');
    try out.flush();
}

fn readInput(self: *Repl) ![]u8 {
    var input: std.ArrayList(u8) = .empty;
    errdefer input.deinit(self.gpa);

    var is_first_line = true;

    while (true) {
        const line = try self.rl.readLineWithHistory(
            if (is_first_line) prompt else continuation_prompt,
            false,
        );
        defer self.gpa.free(line);

        if (!is_first_line) try input.append(self.gpa, '\n');
        try input.appendSlice(self.gpa, line);

        if (try inputIsComplete(input.items)) break;
        is_first_line = false;
    }

    const owned = try input.toOwnedSlice(self.gpa);
    errdefer self.gpa.free(owned);
    if (std.mem.trim(u8, owned, " \t\r\n").len != 0) {
        try self.rl.appendHistory(owned);
    }
    return owned;
}

pub fn render(out: anytype, gpa: Allocator, source: []const u8, mode: AstMode) !void {
    var parser = try Parser.init(gpa, source);
    defer parser.deinit();

    const node = try parser.parse();
    defer node.deinit(gpa);

    switch (mode) {
        .off => try out.writeAll("ok"),
        .tree => try node.writeTreeColored(out),
        .source => try node.writeSource(out),
    }
}

fn handleCommand(self: *Repl, line: []const u8) !bool {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return true;

    if (std.mem.eql(u8, trimmed, ":ast") or std.mem.eql(u8, trimmed, ".ast")) {
        self.ast_mode = self.ast_mode.next();
        try stderr.print("ast mode: {s}\n", .{self.ast_mode.label()});
        try stderr.flush();
        return true;
    }

    if (std.mem.startsWith(u8, trimmed, ":ast ") or std.mem.startsWith(u8, trimmed, ".ast ")) {
        const value = std.mem.trim(u8, trimmed[5..], " \t");
        if (std.mem.eql(u8, value, "off")) {
            self.ast_mode = .off;
        } else if (std.mem.eql(u8, value, "tree")) {
            self.ast_mode = .tree;
        } else if (std.mem.eql(u8, value, "source")) {
            self.ast_mode = .source;
        } else {
            return error.InvalidAstMode;
        }

        try stderr.print("ast mode: {s}\n", .{self.ast_mode.label()});
        try stderr.flush();
        return true;
    }

    return false;
}

fn welcomeMessage() !void {
    try stderr.print("{s}lx{s} runtime {s}\n", .{
        ansi.bold ++ ansi.red,
        ansi.reset,
        build_options.version,
    });
    try stderr.print("ast mode: off\n", .{});
    try stderr.flush();
}

fn inputIsComplete(source: []const u8) !bool {
    if (std.mem.trim(u8, source, " \t\r\n").len == 0) return true;

    var lexer = try Lexer.init(source);
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var bracket_depth: usize = 0;
    var first_top_level: ?Token.Tag = null;
    var saw_top_level_semicolon = false;
    var last_significant: ?Token.Tag = null;

    while (true) {
        const token = lexer.nextToken();
        switch (token.tag) {
            .comment, .newline => {},
            .eof => break,
            .string_open => return false,
            else => {
                if (first_top_level == null and paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) {
                    first_top_level = token.tag;
                }

                switch (token.tag) {
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
                        if (bracket_depth != 0) bracket_depth -= 1;
                    },
                    .semicolon => if (paren_depth == 0 and brace_depth == 0 and bracket_depth == 0) {
                        saw_top_level_semicolon = true;
                    },
                    else => {},
                }

                last_significant = token.tag;
            },
        }
    }

    if (paren_depth != 0 or brace_depth != 0 or bracket_depth != 0) return false;

    if (first_top_level == .let and !saw_top_level_semicolon) return false;

    const last = last_significant orelse return true;
    return switch (last) {
        .semicolon,
        .assign,
        .question,
        .fat_arrow,
        .comma,
        .plus,
        .concat,
        .minus,
        .star,
        .slash,
        .percent,
        .equal,
        .not_equal,
        .greater,
        .greater_equal,
        .less,
        .less_equal,
        .not,
        .range,
        .let,
        .lparen,
        .lbrace,
        .lbracket,
        => false,
        else => true,
    };
}

const testing = std.testing;

test "input completeness for simple expression" {
    try testing.expect(try inputIsComplete("42"));
}

test "input completeness for let binding requires continuation" {
    try testing.expect(!(try inputIsComplete("let answer = 42")));
    try testing.expect(!(try inputIsComplete("let answer = 42;")));
    try testing.expect(try inputIsComplete("let answer = 42;\nanswer"));
}

test "input completeness for multiline function" {
    try testing.expect(!(try inputIsComplete(
        \\let abs = (n) {
    )));
    try testing.expect(!(try inputIsComplete(
        \\let abs = (n) {
        \\    ? n >= 0 => n
        \\    => -n
    )));
    try testing.expect(try inputIsComplete(
        \\let abs = (n) {
        \\    ? n >= 0 => n
        \\    => -n
        \\};
        \\abs(-5)
    ));
}
