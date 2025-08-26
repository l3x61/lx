const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

pub const name = "#env";

pub fn function(_: Value, env: *Environment, _: ?*Environment) anyerror!Value {
    env.debug();
    // TODO: once tables are implemented it should return the env as table
    return Value.Null.init();
}
