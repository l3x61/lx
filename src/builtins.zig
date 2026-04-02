const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const Value = @import("value.zig").Value;

pub fn install(gc: *Gc, env: *Environment) !void {
    try buildIn(gc, env, @import("native/print.zig").name, @import("native/print.zig").function);
    try buildIn(gc, env, @import("native/exit.zig").name, @import("native/exit.zig").function);
}

fn buildIn(
    gc: *Gc,
    env: *Environment,
    name: []const u8,
    function: *const fn (arguments: []const Value) anyerror!Value,
) !void {
    const value = try Value.Native.init(gc.allocator(), name, function);
    try gc.track(value);
    try env.bind(name, value);
}
