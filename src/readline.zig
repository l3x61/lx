const std = @import("std");
const ArrayList = std.ArrayList;
const Writer = std.io.Writer;

const fmt = std.fmt;

const posix = std.posix;
const termios = posix.termios;
const STDIN_FILENO = posix.STDIN_FILENO;

const mem = std.mem;
const Allocator = mem.Allocator;
const zeroes = mem.zeroes;
const bytesToValue = mem.bytesToValue;

const ansi = @import("ansi.zig");
const key = @import("key.zig");
const String = ArrayList(u8);

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

pub fn deinit(self: *ReadLine) void {
    for (self.history.items) |*item| item.deinit(self.gpa);
    self.history.deinit(self.gpa);
}

/// caller does not own the returned String
pub fn readLine(self: *ReadLine, prompt: []const u8) !String {
    try self.out.writeAll(prompt);
    try self.out.flush();

    const raw = try uncook();
    errdefer cook(raw) catch unreachable;

    var line: String = .empty;
    errdefer line.deinit(self.gpa);
    var line_pos: usize = 0;

    const start_row, const start_col = try getCursorPosition(self.out);
    var cursor_col: usize = start_col;

    // -1:       scratch
    // 0..len-1: history where 0 is the most recent entry
    var history_index: isize = -1;
    var scratch: String = .empty;
    errdefer scratch.deinit(self.gpa);

    while (true) {
        const Buffer = [@sizeOf(u64)]u8;
        var buf: Buffer = zeroes(Buffer);
        const bytes = try readBytes(&buf);

        switch (bytesToValue(u64, bytes)) {
            0x00...0x02 => continue,

            key.ctrl_c => return error.Interrupted,

            0x04...0x0C => continue,

            key.enter => {
                var saved: String = .empty;
                errdefer saved.deinit(self.gpa);
                try saved.appendSlice(self.gpa, line.items);
                try self.history.append(self.gpa, saved);

                history_index = -1;
                scratch.clearRetainingCapacity();

                const output = "\n\r";
                try line.appendSlice(self.gpa, output);
                try self.out.writeAll(output);
                try self.out.flush();

                break;
            },

            0x0E...0x1F => continue,

            key.arrow_up => {
                if (self.history.items.len == 0) continue;

                if (history_index == -1) {
                    // backup live edit
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
                    cursor_col = start_col + utf8CountCodepoints(line.items);
                }
            },

            key.arrow_down => {
                if (self.history.items.len == 0) continue;

                if (history_index > 0) {
                    history_index -= 1;
                    const index = self.history.items.len - 1 - @as(usize, @intCast(history_index));
                    const entry = self.history.items[index];
                    line.clearRetainingCapacity();
                    try line.appendSlice(self.gpa, entry.items);
                    line_pos = line.items.len;
                    cursor_col = start_col + utf8CountCodepoints(line.items);
                } else if (history_index == 0) {
                    // restore live edit
                    history_index = -1;
                    line.clearRetainingCapacity();
                    try line.appendSlice(self.gpa, scratch.items);
                    line_pos = line.items.len;
                    cursor_col = start_col + utf8CountCodepoints(line.items);
                }
            },

            key.arrow_left => {
                if (line_pos > 0) {
                    const prev = utf8PreviousCodepoint(line.items, line_pos);
                    line_pos = prev;
                    cursor_col -= 1;
                    try self.out.writeAll("\x1b[1D");
                    try self.out.flush();
                }
            },

            key.arrow_right => {
                if (line_pos < line.items.len) {
                    const next = utf8NextCodepoint(line.items, line_pos);
                    line_pos = next;
                    cursor_col += 1;
                    try self.out.writeAll("\x1b[1C");
                    try self.out.flush();
                }
            },

            key.backslash => {
                const output = "λ";
                try line.insertSlice(self.gpa, line_pos, output);
                line_pos += output.len;
                cursor_col += 1;
            },

            key.backspace => {
                if (line_pos > 0) {
                    const start = utf8PreviousCodepoint(line.items, line_pos);
                    const del_len = line_pos - start;
                    try line.replaceRange(self.gpa, start, del_len, &[_]u8{});
                    line_pos = start;
                    cursor_col -= 1;
                }
            },

            else => {
                try line.insertSlice(self.gpa, line_pos, bytes);
                line_pos += bytes.len;
                cursor_col += utf8CountCodepoints(bytes);
            },
        }

        try setCursorPos(self.out, start_row, start_col);
        try self.out.writeAll(ansi.erase_to_end);
        try self.out.writeAll(line.items);
        try self.out.flush();
        try setCursorPos(self.out, start_row, cursor_col);
    }

    try cook(raw);
    return line;
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
    try out.writeAll(ansi.get_cursor_position);
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

fn uncook() !termios {
    const cooked = try posix.tcgetattr(STDIN_FILENO);

    var raw = cooked;

    // https://www.man7.org/linux/man-pages/man3/termios.3.html
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.iflag.IXON = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.ICRNL = false;
    raw.oflag.OPOST = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.cflag.CSIZE = .CS8;
    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(posix.V.TIME)] = 1;

    try posix.tcsetattr(STDIN_FILENO, .FLUSH, raw);

    return cooked;
}

fn cook(raw: termios) !void {
    try posix.tcsetattr(STDIN_FILENO, .FLUSH, raw);
}
