const std = @import("std");
const log = std.log.scoped(.builtin_exit);
const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

pub const name = "exit";

pub fn function(arg: Value, _: *Environment, _: ?*Environment) anyerror!Value {
    if (arg.asNumber()) |status| {
        std.process.exit(@intFromFloat(status));
    }
    log.warn("expected a number but got {f} instead\n", .{arg.tag()});
    return error.TypeError;
}
