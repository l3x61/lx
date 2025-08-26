const std = @import("std");
const ansi = @import("../ansi.zig");
const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

const capture_name = "__capture";

pub const name = "+";

pub fn function(argument: Value, env: *Environment, capture_env: ?*Environment) anyerror!Value {
    if (capture_env) |cenv| {
        const capture = try cenv.lookup(capture_name);
        if (capture.asNumber()) |a| {
            if (argument.asNumber()) |b| {
                return Value.Number.init(a + b);
            }
        }
        std.debug.print("can not add {s}{s}{s} to {s}{s}{s}\n", .{
            ansi.dimmed,
            capture,
            ansi.reset,
            ansi.dimmed,
            argument,
            ansi.reset,
        });
        return error.InvalidArguments;
    }

    var child = try Environment.init(env.allocator, env);
    try child.define(env.allocator, capture_name, argument);
    return Value.Builtin.init(name ++ " ?", function, child);
}
