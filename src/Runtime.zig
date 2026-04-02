const std = @import("std");
const Allocator = std.mem.Allocator;

const Parser = @import("Parser.zig");
const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const Value = @import("value.zig").Value;
const evaluate = @import("evaluate.zig").evaluate;
const builtins = @import("builtins.zig");

const Runtime = @This();

gpa: Allocator,
gc: Gc,
globals: *Environment,

pub fn init(gpa: Allocator) !Runtime {
    var gc = try Gc.init(gpa);
    errdefer gc.deinit();

    const globals = try Environment.init(gc.allocator(), null);
    errdefer globals.deinit();

    try gc.track(globals);

    var runtime = Runtime{
        .gpa = gpa,
        .gc = gc,
        .globals = globals,
    };

    try builtins.install(&runtime.gc, runtime.globals);
    return runtime;
}

pub fn deinit(self: *Runtime) void {
    self.gc.deinit();
}

pub fn evaluateSource(self: *Runtime, source: []const u8) !Value {
    const owned_source = try self.gc.allocator().dupe(u8, source);
    errdefer self.gc.allocator().free(owned_source);
    try self.gc.track(owned_source);

    var parser = try Parser.init(self.gc.allocator(), owned_source);
    defer parser.deinit();

    const ast = try parser.parse();
    errdefer ast.deinit(self.gc.allocator());
    try self.gc.track(ast);

    return evaluate(ast, &self.gc, self.globals);
}

const testing = std.testing;

test "evaluate source through runtime" {
    var runtime = try Runtime.init(testing.allocator);
    defer runtime.deinit();

    const value = try runtime.evaluateSource(
        \\let add = (x, y) { x + y };
        \\add(1, 2)
    );

    try testing.expect(value.equal(.{ .number = 3 }));
}
