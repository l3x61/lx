const std = @import("std");

const Value = @import("../value.zig").Value;

pub const name = "exit";

pub fn function(arguments: []const Value) !Value {
    if (arguments.len != 1) return error.ArityMismatch;
    const status = arguments[0].asNumber() orelse return error.TypeError;
    std.process.exit(@intFromFloat(status));
}
