const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

pub const name = "exit";

pub fn function(_: Value, _: *Environment, _: ?*Environment) anyerror!Value {
    return error.NormalExit;
}
