// https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797
//
// https://ecma-international.org/publications-and-standards/standards/ecma-48/
// https://ecma-international.org/wp-content/uploads/ECMA-48_2nd_edition_august_1979.pdf

// TODO: disable color setting

pub const esc = "\x1B";
pub const csi = "[";

pub const reset = esc ++ csi ++ "0m";
pub const bold = esc ++ csi ++ "1m";
pub const dimmed = esc ++ csi ++ "2m";
pub const italic = esc ++ csi ++ "3m";
pub const underline = esc ++ csi ++ "4m";
pub const blink = esc ++ csi ++ "5m";
pub const reverse = esc ++ csi ++ "7m";
pub const hidden = esc ++ csi ++ "8m";
pub const strikethrough = esc ++ csi ++ "9m";

pub const black = esc ++ csi ++ "30m";
pub const red = esc ++ csi ++ "31m";
pub const green = esc ++ csi ++ "32m";
pub const yellow = esc ++ csi ++ "33m";
pub const blue = esc ++ csi ++ "34m";
pub const magenta = esc ++ csi ++ "35m";
pub const cyan = esc ++ csi ++ "36m";
pub const white = esc ++ csi ++ "37m";

pub const erase_to_end = esc ++ csi ++ "0K";
pub const erase_to_start = esc ++ csi ++ "1K";
pub const erase_line = esc ++ csi ++ "2K";

pub const move_cursor_left = esc ++ csi ++ "1D";
pub const move_cursor_right = esc ++ csi ++ "1C";
pub const move_cursor_up = esc ++ csi ++ "1A";
pub const move_cursor_down = esc ++ csi ++ "1B";

pub const get_cursor_position = esc ++ csi ++ "6n";
