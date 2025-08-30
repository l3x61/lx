const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.io.Reader;
const Writer = std.io.Writer;

const posix = std.posix;
const termios = posix.termios;
const STDIN_FILENO = posix.STDIN_FILENO;

const mem = std.mem;
const zeroes = mem.zeroes;
const bytesToValue = mem.bytesToValue;

const ansi = @import("ansi.zig");
const key = @import("key.zig");
const String = @import("String.zig");

pub fn readLine(ator: Allocator, prompt: []const u8, out: *Writer) !String {
    try out.writeAll(prompt);
    try out.flush();

    const raw = try uncook();
    errdefer cook(raw) catch unreachable;

    var line: String = .empty;
    errdefer line.deinit(ator);

    const start_row, const start_col = try getCursorPosition(out);

    var cursor_col = start_col;

    const Buffer = [@sizeOf(u64)]u8;
    var buffer: Buffer = undefined;
    while (true) {
        buffer = zeroes(Buffer);

        const bytes = try readBytes(&buffer);
        const value = bytesToValue(u64, bytes);

        switch (value) {
            0x00...0x02 => continue,
            key.ctrl_c => return error.Interrupted,
            0x04...0x0C => continue,
            key.enter => {
                const output = "\n\r";
                try line.appendSlice(ator, output);
                try out.writeAll(output);
                try out.flush();
                break;
            },
            0x0E...0x1F => continue,
            key.arrow_left => {
                if (cursor_col > start_col) {
                    cursor_col -= 1;
                    try out.writeAll("\x1b[1D");
                    try out.flush();
                }
            },
            key.arrow_right => {
                if (cursor_col < start_col + line.getSlice().len) {
                    cursor_col += 1;
                    try out.writeAll("\x1b[1C");
                    try out.flush();
                }
            },
            key.backslash => {
                const output = "λ";
                try line.insertSlice(ator, cursor_col - start_col, output);
                cursor_col += 1;
            },
            key.backspace => {
                if (cursor_col > start_col) {
                    const end = cursor_col - start_col;
                    const start = previousCodepoint(line.getSlice(), end);
                    const del_len = end - start;

                    try line.replaceRange(ator, start, del_len, &[_]u8{});

                    cursor_col -= del_len;
                }
            },
            else => {
                // std.debug.print("{x}", .{value});
                try line.insertSlice(ator, cursor_col - start_col, bytes);
                cursor_col += 1;
            },
        }

        try setCursorPos(out, start_row, start_col);
        try out.writeAll(ansi.erase_to_end);
        try out.writeAll(line.getSlice());
        try out.flush();
        try setCursorPos(out, start_row, cursor_col);
    }

    try cook(raw);

    return line;
}

fn previousCodepoint(s: []const u8, index: usize) usize {
    if (index == 0) {
        return 0;
    }
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
    var it = std.mem.splitScalar(u8, response, ';');
    const row_str = it.next() orelse return error.BadResponse;
    const col_str = it.next() orelse return error.BadResponse;

    const row = try std.fmt.parseInt(usize, row_str, 10);
    const col = try std.fmt.parseInt(usize, col_str, 10);
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
