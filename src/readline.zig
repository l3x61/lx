const std = @import("std");
const ArrayList = std.ArrayList;
const Writer = std.Io.Writer;
const Terminal = std.Io.Terminal;

const fmt = std.fmt;

const posix = std.posix;
const termios = posix.termios;
const STDIN_FILENO = posix.STDIN_FILENO;

const mem = std.mem;
const Allocator = mem.Allocator;
const zeroes = mem.zeroes;
const bytesToValue = mem.bytesToValue;

const term = @import("term.zig");
const Token = @import("Token.zig");
const Lexer = @import("Lexer.zig");
const String = ArrayList(u8);

// https://github.com/termbox/termbox2/blob/290ac6b8225aacfd16851224682b851b65fcb918/termbox2.h#L122
const KeyCode = enum(u64) {
    ctrl_c = 0x03,
    ctrl_d = 0x04,
    enter = 0x0D,
    shift_enter = 0x0A,
    backspace = 0x7F,
    arrow_left = 0x44_5B_1B,
    arrow_right = 0x43_5B_1B,
    arrow_up = 0x41_5B_1B,
    arrow_down = 0x42_5B_1B,
};

const ReadLine = @This();

gpa: Allocator,
out: *Writer,
history: ArrayList(String),

pub fn init(gpa: Allocator, out: *Writer) ReadLine {
    return ReadLine{
        .gpa = gpa,
        .out = out,
        .history = ArrayList(String).empty,
    };
}

fn terminal(self: *const ReadLine) Terminal {
    return term.wrap(self.out);
}

pub fn deinit(self: *ReadLine) void {
    for (self.history.items) |*item| item.deinit(self.gpa);
    self.history.deinit(self.gpa);
}

pub fn readLine(self: *ReadLine, prompt: []const u8) ![]u8 {
    return self.readLineWithHistory(prompt, true);
}

pub fn readLineWithHistory(self: *ReadLine, prompt: []const u8, save_history: bool) ![]u8 {
    try self.out.writeAll(prompt);
    try self.out.flush();

    const raw = try uncook();
    errdefer cook(raw) catch unreachable;

    var line: String = .empty;
    errdefer line.deinit(self.gpa);
    var line_pos: usize = 0;

    var history_index: isize = -1;
    var scratch: String = .empty;
    errdefer scratch.deinit(self.gpa);

    while (true) {
        const Buffer = [@sizeOf(u64)]u8;
        var buf: Buffer = zeroes(Buffer);
        const bytes = try readBytes(&buf);

        switch (bytesToValue(u64, bytes)) {
            0x00...0x02 => continue,

            @intFromEnum(KeyCode.ctrl_c) => return error.Interrupted,

            0x04...0x0C => continue,

            @intFromEnum(KeyCode.enter) => {
                if (save_history) try self.appendHistory(line.items);

                history_index = -1;
                scratch.clearRetainingCapacity();

                try self.out.writeAll("\r\n");
                try self.out.flush();
                break;
            },

            0x0E...0x1F => continue,

            @intFromEnum(KeyCode.arrow_up) => {
                if (self.history.items.len == 0) continue;
                if (history_index == -1) {
                    scratch.clearRetainingCapacity();
                    try scratch.appendSlice(self.gpa, line.items);
                }
                if (history_index < @as(isize, @intCast(self.history.items.len - 1))) {
                    history_index += 1;
                    const index = self.history.items.len - 1 - @as(usize, @intCast(history_index));
                    const entry = self.history.items[index];
                    line.clearRetainingCapacity();
                    try line.appendSlice(self.gpa, entry.items);
                    line_pos = line.items.len;
                }
            },

            @intFromEnum(KeyCode.arrow_down) => {
                if (self.history.items.len == 0) continue;
                if (history_index > 0) {
                    history_index -= 1;
                    const index = self.history.items.len - 1 - @as(usize, @intCast(history_index));
                    const entry = self.history.items[index];
                    line.clearRetainingCapacity();
                    try line.appendSlice(self.gpa, entry.items);
                    line_pos = line.items.len;
                } else if (history_index == 0) {
                    history_index = -1;
                    line.clearRetainingCapacity();
                    try line.appendSlice(self.gpa, scratch.items);
                    line_pos = line.items.len;
                }
            },

            @intFromEnum(KeyCode.arrow_left) => {
                if (line_pos > 0) {
                    line_pos = utf8PreviousCodepoint(line.items, line_pos);
                }
            },

            @intFromEnum(KeyCode.arrow_right) => {
                if (line_pos < line.items.len) {
                    line_pos = utf8NextCodepoint(line.items, line_pos);
                }
            },

            @intFromEnum(KeyCode.backspace) => {
                if (line_pos > 0) {
                    const start = utf8PreviousCodepoint(line.items, line_pos);
                    const del_len = line_pos - start;
                    try line.replaceRange(self.gpa, start, del_len, &[_]u8{});
                    line_pos = start;
                }
            },

            else => {
                try line.insertSlice(self.gpa, line_pos, bytes);
                line_pos += bytes.len;
            },
        }

        try self.out.writeAll("\r");
        try self.out.writeAll(term.erase_to_end);
        try self.out.writeAll(prompt);
        try writeColored(self.terminal(), line.items);
        try self.out.flush();

        const tail_cols = utf8CountCodepoints(line.items[line_pos..]);
        if (tail_cols > 0) {
            try self.out.print("\x1b[{d}D", .{tail_cols});
            try self.out.flush();
        }
    }

    try cook(raw);
    return line.toOwnedSlice(self.gpa);
}

pub fn appendHistory(self: *ReadLine, source: []const u8) !void {
    var saved: String = .empty;
    errdefer saved.deinit(self.gpa);
    try saved.appendSlice(self.gpa, source);
    try self.history.append(self.gpa, saved);
}

fn utf8CountCodepoints(bytes: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        if ((bytes[i] & 0xC0) != 0x80) n += 1;
    }
    return n;
}

fn utf8NextCodepoint(s: []const u8, index: usize) usize {
    var i = index + 1;
    while (i < s.len and (s[i] & 0xC0) == 0x80) : (i += 1) {}
    return i;
}

fn utf8PreviousCodepoint(s: []const u8, index: usize) usize {
    if (index == 0) return 0;
    var i = index - 1;
    while (i > 0 and (s[i] & 0xC0) == 0x80) : (i -= 1) {}
    return i;
}

fn getCursorPosition(out: *Writer) ![2]usize {
    try out.writeAll(term.get_cursor_position);
    try out.flush();

    const Buffer = [@sizeOf(u64)]u8;
    var buffer: Buffer = zeroes(Buffer);

    const bytes = try readBytes(&buffer);

    const response = bytes[2 .. bytes.len - 1];
    var it = mem.splitScalar(u8, response, ';');
    const row_str = it.next() orelse return error.BadResponse;
    const col_str = it.next() orelse return error.BadResponse;

    const row = try fmt.parseInt(usize, row_str, 10);
    const col = try fmt.parseInt(usize, col_str, 10);
    return .{ row, col };
}

fn setCursorPos(out: *Writer, row: usize, col: usize) !void {
    try out.print("\x1b[{d};{d}H", .{ row, col });
    try out.flush();
}

fn readBytes(buffer: []u8) ![]const u8 {
    while (true) {
        const bytes_read = posix.read(STDIN_FILENO, buffer) catch |err| {
            switch (err) {
                error.WouldBlock => continue,
                else => return err,
            }
        };
        if (bytes_read >= 1) {
            return buffer[0..bytes_read];
        }
    }
}

fn writeColored(t: Terminal, source: []const u8) !void {
    if (isCommandLine(source)) {
        try writeCommandColored(t, source);
        return;
    }

    var lexer = try Lexer.init(source);
    var prev_token_index: usize = 0;

    while (true) {
        const token = lexer.nextToken();
        if (token.tag == Token.Tag.eof) break;

        const token_index = @intFromPtr(token.lexeme.ptr) - @intFromPtr(token.source.ptr);
        if (token_index > prev_token_index) {
            try t.writer.writeAll(source[prev_token_index..token_index]);
        }

        try t.setColor(token.color());
        try t.writer.writeAll(token.lexeme);
        try t.setColor(.reset);

        prev_token_index = token_index + token.lexeme.len;
    }

    if (prev_token_index < source.len) {
        try t.writer.writeAll(source[prev_token_index..source.len]);
    }
}

fn isCommandLine(source: []const u8) bool {
    const trimmed_left = mem.trimStart(u8, source, " \t");
    if (trimmed_left.len == 0) return false;
    return trimmed_left[0] == '.' or trimmed_left[0] == ':';
}

fn writeCommandColored(t: Terminal, source: []const u8) !void {
    const out = t.writer;
    const leading_len = source.len - mem.trimStart(u8, source, " \t").len;
    if (leading_len != 0) try out.writeAll(source[0..leading_len]);

    const rest = source[leading_len..];
    const command_end = mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    const command = rest[0..command_end];
    try t.setColor(.bold);
    try t.setColor(.cyan);
    try out.writeAll(command);
    try t.setColor(.reset);

    var tail = rest[command_end..];
    while (tail.len != 0) {
        const ws_len = tail.len - mem.trimStart(u8, tail, " \t").len;
        if (ws_len != 0) {
            try out.writeAll(tail[0..ws_len]);
            tail = tail[ws_len..];
            continue;
        }

        const token_end = mem.indexOfAny(u8, tail, " \t") orelse tail.len;
        const token = tail[0..token_end];
        try t.setColor(colorForCommandToken(command, token));
        try out.writeAll(token);
        try t.setColor(.reset);
        tail = tail[token_end..];
    }
}

fn colorForCommandToken(command: []const u8, token: []const u8) Terminal.Color {
    if (mem.eql(u8, command, ".ast") or mem.eql(u8, command, ":ast")) {
        if (mem.eql(u8, token, "tree")) return .magenta;
        if (mem.eql(u8, token, "off")) return .dim;
        return .red;
    }

    return .yellow;
}

fn uncook() !termios {
    const cooked = try posix.tcgetattr(STDIN_FILENO);
    var raw = cooked;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;

    raw.oflag.OPOST = false;

    raw.cflag.CSIZE = .CS8;

    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(posix.V.TIME)] = 1;

    try posix.tcsetattr(STDIN_FILENO, .FLUSH, raw);
    return cooked;
}

fn cook(raw: termios) !void {
    try posix.tcsetattr(STDIN_FILENO, .FLUSH, raw);
}
