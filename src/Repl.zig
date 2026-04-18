const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Terminal = Io.Terminal;
const max_path_bytes = Io.Dir.max_path_bytes;

const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const ReadLine = @import("readline.zig");
const Runtime = @import("Runtime.zig");
const Token = @import("Token.zig");

const Repl = @This();

const csi = "\x1b[";
const prompt = csi ++ "36m" ++ "> " ++ csi ++ "0m";
const continuation_prompt = csi ++ "2m" ++ "| " ++ csi ++ "0m";

pub const AstMode = enum {
    off,
    tree,

    pub fn next(self: AstMode) AstMode {
        return switch (self) {
            .off => .tree,
            .tree => .off,
        };
    }

    pub fn state(self: AstMode) []const u8 {
        return switch (self) {
            .off => "off",
            .tree => "tree",
        };
    }
};

gpa: Allocator,
io: Io,
stdout_buffer: [max_path_bytes]u8,
stderr_buffer: [max_path_bytes]u8,
stdout_writer: Io.File.Writer,
stderr_writer: Io.File.Writer,
rl: ReadLine,
ast_mode: AstMode,
runtime: Runtime,

pub fn init(gpa: Allocator, io: Io) !*Repl {
    const self = try gpa.create(Repl);
    errdefer gpa.destroy(self);

    self.* = .{
        .gpa = gpa,
        .io = io,
        .stdout_buffer = undefined,
        .stderr_buffer = undefined,
        .stdout_writer = undefined,
        .stderr_writer = undefined,
        .rl = undefined,
        .ast_mode = .off,
        .runtime = try Runtime.init(gpa, io),
    };

    self.stdout_writer = Io.File.stdout().writer(io, &self.stdout_buffer);
    self.stderr_writer = Io.File.stderr().writer(io, &self.stderr_buffer);
    self.rl = ReadLine.init(gpa, &self.stdout_writer.interface);
    return self;
}

pub fn deinit(self: *Repl) void {
    self.runtime.deinit();
    self.rl.deinit();
    self.gpa.destroy(self);
}

pub fn run(self: *Repl) !void {
    try self.welcomeMessage();

    while (true) {
        const line = self.readInput() catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };
        defer self.gpa.free(line);

        const handled = self.handleCommand(line) catch |err| {
            try self.stderr().print("{t}\n", .{err});
            try self.stderr().flush();
            continue;
        };
        if (handled) continue;

        self.renderLine(line) catch |err| {
            try self.stderr().print("{t}\n", .{err});
            try self.stderr().flush();
            continue;
        };
    }
}

fn stdout(self: *Repl) *Io.Writer {
    return &self.stdout_writer.interface;
}

fn stderr(self: *Repl) *Io.Writer {
    return &self.stderr_writer.interface;
}

fn stdoutTerminal(self: *Repl) Terminal {
    return wrapTerminal(self.stdout());
}

fn stderrTerminal(self: *Repl) Terminal {
    return wrapTerminal(self.stderr());
}

fn wrapTerminal(writer: *Io.Writer) Terminal {
    return .{ .writer = writer, .mode = .escape_codes };
}

fn renderLine(self: *Repl, source: []const u8) !void {
    const out = self.stdout();
    if (self.ast_mode == .off) {
        const value = self.runtime.evaluateSourceNamed("<repl>", source) catch |err| switch (err) {
            error.SyntaxError => {
                if (self.runtime.last_parse_error) |diagnostic| {
                    try diagnostic.write(self.stderrTerminal());
                    try self.stderr().flush();
                    return;
                }
                return err;
            },
            else => return err,
        };
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

    render(
        self.stdoutTerminal(),
        self.stderrTerminal(),
        self.gpa,
        "<repl>",
        source,
        self.ast_mode,
    ) catch |err| switch (err) {
        error.SyntaxError => {
            try self.stderr().flush();
            return;
        },
        else => return err,
    };
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

pub fn render(out: Terminal, err: Terminal, gpa: Allocator, source_name: []const u8, source: []const u8, mode: AstMode) !void {
    var parser = try Parser.initNamed(gpa, source_name, source);
    defer parser.deinit();

    const node = parser.parse() catch |parse_err| switch (parse_err) {
        error.SyntaxError => {
            if (parser.last_error) |diagnostic| try diagnostic.write(err);
            return parse_err;
        },
        else => return parse_err,
    };
    defer node.deinit(gpa);

    switch (mode) {
        .off => try out.writer.writeAll("ok"),
        .tree => try node.writeTree(out),
    }
}

fn handleCommand(self: *Repl, line: []const u8) !bool {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return true;

    if (std.mem.eql(u8, trimmed, ":ast") or std.mem.eql(u8, trimmed, ".ast")) {
        self.ast_mode = self.ast_mode.next();
        try self.stderr().print("ast mode: {s}\n", .{self.ast_mode.state()});
        try self.stderr().flush();
        return true;
    }

    if (std.mem.startsWith(u8, trimmed, ":ast ") or std.mem.startsWith(u8, trimmed, ".ast ")) {
        const value = std.mem.trim(u8, trimmed[5..], " \t");
        if (std.mem.eql(u8, value, "off")) {
            self.ast_mode = .off;
        } else if (std.mem.eql(u8, value, "tree")) {
            self.ast_mode = .tree;
        } else {
            return error.InvalidAstMode;
        }

        try self.stderr().print("ast mode: {s}\n", .{self.ast_mode.state()});
        try self.stderr().flush();
        return true;
    }

    return false;
}

fn welcomeMessage(self: *Repl) !void {
    const t = self.stderrTerminal();
    try t.setColor(.bold);
    try t.setColor(.red);
    try t.writer.writeAll("lx");
    try t.setColor(.reset);
    try t.writer.print(" runtime {s}\n", .{build_options.version});
    try t.writer.writeAll("ast mode: off\n");
    try t.writer.flush();
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
