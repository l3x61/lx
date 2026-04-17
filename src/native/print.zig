const std = @import("std");
const Io = std.Io;

const Value = @import("../value.zig").Value;

pub const name = "print";

pub fn function(io: Io, arguments: []const Value) !Value {
    if (arguments.len != 1) return error.ArityMismatch;

    var buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &buffer);
    try arguments[0].display(&stdout_writer.interface);
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.interface.flush();
    return .{ .unit = {} };
}
