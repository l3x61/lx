const Environment = @import("../Environment.zig");
const Value = @import("../value.zig").Value;

pub fn exit(_: Value, _: *Environment) anyerror!Value {
    return error.NormalExit;
}
