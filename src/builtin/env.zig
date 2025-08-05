const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

pub fn env(_: Value, e: *Environment) anyerror!Value {
    e.debug();
    // TODO: once tables are implemented it should return the env as table
    return Value.Null.init();
}
