const std = @import("std");
const Io = std.Io;

const Value = @import("../value.zig").Value;

pub const name = "exit";

pub fn function(io: Io, arguments: []const Value) !Value {
    _ = io;
    if (arguments.len != 1) return error.ArityMismatch;
    const status = arguments[0].asNumber() orelse return error.TypeError;
    std.process.exit(@intFromFloat(status));
}
