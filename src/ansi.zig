// https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
//
// https://ecma-international.org/publications-and-standards/standards/ecma-48/
// https://ecma-international.org/wp-content/uploads/ECMA-48_2nd_edition_august_1979.pdf

// TODO: disable color setting

pub const escape = "\x1B";

/// control_sequence_introducer
pub const csi = escape ++ "[";

pub const reset = csi ++ "0m";
pub const bold = csi ++ "1m";
pub const dim = csi ++ "2m";
pub const italic = csi ++ "3m";
pub const underline = csi ++ "4m";
pub const blink = csi ++ "5m";
pub const reverse = csi ++ "7m";
pub const hidden = csi ++ "8m";
pub const strikethrough = csi ++ "9m";

pub const black = csi ++ "30m";
pub const red = csi ++ "31m";
pub const green = csi ++ "32m";
pub const yellow = csi ++ "33m";
pub const blue = csi ++ "34m";
pub const magenta = csi ++ "35m";
pub const cyan = csi ++ "36m";
pub const white = csi ++ "37m";

pub const erase_to_end = csi ++ "0K";
pub const erase_to_start = csi ++ "1K";
pub const erase_line = csi ++ "2K";

pub const move_cursor_left = csi ++ "1D";
pub const move_cursor_right = csi ++ "1C";
pub const move_cursor_up = csi ++ "1A";
pub const move_cursor_down = csi ++ "1B";

pub const get_cursor_position = csi ++ "6n";
