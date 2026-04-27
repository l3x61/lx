const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const testing = std.testing;

const builtins = @import("builtins.zig");
const Environment = @import("Environment.zig");
const evaluate = @import("evaluate.zig").evaluate;
const Gc = @import("Gc.zig");
const Parser = @import("Parser.zig");
const Value = @import("value.zig").Value;

const Runtime = @This();

gc: Gc,
globals: *Environment,
last_parse_error: ?Parser.Diagnostic,

pub fn init(gpa: Allocator, io: Io) !Runtime {
    var gc = try Gc.init(gpa, io);
    errdefer gc.deinit();

    const globals = try Environment.init(gc.allocator(), null);
    errdefer globals.deinit();

    try gc.track(globals);

    var runtime = Runtime{
        .gc = gc,
        .globals = globals,
        .last_parse_error = null,
    };

    try builtins.install(&runtime.gc, runtime.globals);
    return runtime;
}

pub fn deinit(self: *Runtime) void {
    self.gc.deinit();
}

pub fn evaluateSource(self: *Runtime, source: []const u8) !Value {
    return self.evaluateSourceNamed("<input>", source);
}

pub fn evaluateSourceNamed(self: *Runtime, source_name: []const u8, source: []const u8) !Value {
    self.last_parse_error = null;
    const owned_source = try self.gc.allocator().dupe(u8, source);

    var parser = Parser.initNamed(self.gc.allocator(), source_name, owned_source) catch |err| {
        self.gc.allocator().free(owned_source);
        return err;
    };
    defer parser.deinit();

    const ast = parser.parse() catch |err| switch (err) {
        error.SyntaxError => {
            self.last_parse_error = parser.last_error;
            self.gc.track(owned_source) catch |track_err| {
                self.gc.allocator().free(owned_source);
                return track_err;
            };
            return err;
        },
        else => {
            self.gc.allocator().free(owned_source);
            return err;
        },
    };

    self.gc.track(owned_source) catch |err| {
        ast.deinit(self.gc.allocator());
        self.gc.allocator().free(owned_source);
        return err;
    };

    self.gc.track(ast) catch |err| {
        ast.deinit(self.gc.allocator());
        return err;
    };

    return evaluate(ast, &self.gc, self.globals);
}

test "evaluate source through runtime" {
    var runtime = try Runtime.init(testing.allocator, testing.io);
    defer runtime.deinit();

    const value = try runtime.evaluateSource(
        \\let add = \ x, y -> x + y;
        \\add(1, 2)
    );

    try testing.expect(value.equal(.{ .integer = 3 }));
}

test "runs current non-print examples" {
    const files = [_][]const u8{
        "examples/abs.lx",
        "examples/classify.lx",
        "examples/head.lx",
        "examples/block.lx",
    };

    var runtime = try Runtime.init(testing.allocator, testing.io);
    defer runtime.deinit();

    for (files) |path| {
        const source = try Io.Dir.cwd().readFileAlloc(testing.io, path, testing.allocator, .limited(16 * 1024 * 1024));
        defer testing.allocator.free(source);
        _ = try runtime.evaluateSourceNamed(path, source);
    }
}
