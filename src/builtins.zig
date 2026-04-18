const std = @import("std");
const Io = std.Io;

const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const Value = @import("value.zig").Value;

pub fn install(gc: *Gc, env: *Environment) !void {
    try buildIn(gc, env, "print", printBuiltin);
    try buildIn(gc, env, "exit", exitBuiltin);
}

fn buildIn(
    gc: *Gc,
    env: *Environment,
    name: []const u8,
    function: *const fn (io: Io, arguments: []const Value) anyerror!Value,
) !void {
    const value = try Value.Native.init(gc.allocator(), name, function);
    try gc.track(value);
    try env.bind(name, value);
}

fn printBuiltin(io: Io, arguments: []const Value) !Value {
    if (arguments.len != 1) return error.ArityMismatch;

    var buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(io, &buffer);
    try arguments[0].display(&stdout_writer.interface);
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.interface.flush();
    return .{ .unit = {} };
}

fn exitBuiltin(io: Io, arguments: []const Value) !Value {
    _ = io;
    if (arguments.len != 1) return error.ArityMismatch;
    const status = arguments[0].asNumber() orelse return error.TypeError;
    std.process.exit(@intFromFloat(status));
}
