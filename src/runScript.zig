const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const evaluate = @import("evaluate.zig").evaluate;
const Parser = @import("Parser.zig");
const Value = @import("value.zig").Value;
const Object = @import("object.zig").Object;

pub fn runScript(gpa: Allocator, script: []const u8) !void {
    const builtin_exit = @import("builtin/exit.zig");

    var env = try Environment.init(gpa, null);
    defer env.deinitAll(gpa);

    try env.define(gpa, builtin_exit.name, Value.Builtin.init(builtin_exit.name, builtin_exit.function, null));

    var objects: ArrayList(Object) = .empty;
    defer {
        for (objects.items) |*object| object.deinit(gpa);
        objects.deinit(gpa);
    }

    var parser = try Parser.init(gpa, script);
    const ast = try parser.parse();
    defer ast.deinit(gpa);

    _ = try evaluate(gpa, ast, env, &objects);
}
