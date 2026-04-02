const std = @import("std");

const Value = @import("../value.zig").Value;

pub const name = "print";

pub fn function(arguments: []const Value) !Value {
    if (arguments.len != 1) return error.ArityMismatch;

    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buffer);
    try arguments[0].display(&stdout_writer.interface);
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.interface.flush();
    return .{ .unit = {} };
}
