const std = @import("std");
const Io = std.Io;

pub const Terminal = Io.Terminal;
pub const Color = Terminal.Color;

pub const csi = "\x1b[";

pub const erase_to_end = csi ++ "0K";
pub const get_cursor_position = csi ++ "6n";

pub fn wrap(writer: *Io.Writer) Terminal {
    return .{ .writer = writer, .mode = .escape_codes };
}
