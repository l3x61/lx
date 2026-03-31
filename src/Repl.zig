const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const max_path_bytes = std.fs.max_path_bytes;

const ansi = @import("ansi.zig");
const Lexer = @import("Lexer.zig");
const ReadLine = @import("readline.zig");
const Token = @import("Token.zig");

const Repl = @This();
const prompt = ansi.cyan ++ "> " ++ ansi.reset;

gpa: Allocator,
rl: ReadLine,

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
    };
}

pub fn deinit(self: *Repl) void {
    self.rl.deinit();
}

pub fn run(self: *Repl) !void {
    try welcomeMessage();

    while (true) {
        const line = self.rl.readLine(prompt) catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };
        defer self.gpa.free(line);

        try dumpTokens(stdout, line);
        try stdout.writeAll("\n");
        try stdout.flush();
    }
}

fn welcomeMessage() !void {
    try stderr.print("{s}lx{s} lexer {s}\n", .{
        ansi.bold ++ ansi.red,
        ansi.reset,
        build_options.version,
    });
    try stderr.flush();
}

pub fn dumpTokens(out: anytype, source: []const u8) !void {
    var lexer = try Lexer.init(source);
    var first = true;

    while (true) {
        const token = lexer.nextToken();
        if (!first) try out.writeAll("\n");
        first = false;

        var escaped_buffer: [512]u8 = undefined;
        const escaped = try escapeLexeme(&escaped_buffer, token.lexeme);
        try out.print("{f:<12} {s}", .{ token.tag, escaped });

        if (token.tag == .eof) break;
    }
}

fn escapeLexeme(buffer: []u8, input: []const u8) ![]const u8 {
    var index: usize = 0;

    for (input) |byte| {
        const escaped: []const u8 = switch (byte) {
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            '\\' => "\\\\",
            else => &[_]u8{byte},
        };

        if (index + escaped.len > buffer.len) return error.NoSpaceLeft;
        @memcpy(buffer[index .. index + escaped.len], escaped);
        index += escaped.len;
    }

    return buffer[0..index];
}
