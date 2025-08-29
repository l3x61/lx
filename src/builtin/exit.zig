const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

pub const name = "exit";

pub fn function(arg: Value, _: *Environment, _: ?*Environment) anyerror!Value {
    @import("std").process.exit(@intFromFloat(arg.asNumber().?));
}
