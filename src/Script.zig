const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const fs = std.fs;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const evaluate = @import("evaluate.zig").evaluate;
const Parser = @import("Parser.zig");
const Value = @import("value.zig").Value;
const Gc = @import("Gc.zig");

const max_file_size = std.math.maxInt(u32);
const Script = @This();

gpa: Allocator,
gc: Gc,
path: []u8,
text: []u8,

pub fn init(gpa: Allocator, path: []const u8) !Script {
    var gc = try Gc.init(gpa);
    errdefer gc.deinit();

    const text = try fs.cwd().readFileAlloc(gpa, path, max_file_size);
    const copy = try gpa.dupe(u8, path);
    return Script{
        .gpa = gpa,
        .gc = gc,
        .path = copy,
        .text = text,
    };
}

pub fn deinit(self: *Script) void {
    self.gc.deinit();
    self.gpa.free(self.text);
    self.gpa.free(self.path);
}

pub fn run(self: *Script, parent_env: ?*Environment) !Value {
    var gc = &self.gc;
    const gpa = gc.allocator();

    var env_tracked = false;
    var env = try Environment.init(gpa, parent_env);
    errdefer if (!env_tracked) env.deinit();

    try gc.track(env);
    env_tracked = true;

    const exit = @import("native/exit.zig");
    var native_tracked = false;
    var native = try Value.Native.init(gpa, exit.name, exit.function, null);
    errdefer if (!native_tracked) native.deinit(gpa);

    try env.bind(exit.name, native);
    try gc.track(native);
    native_tracked = true;

    var parser = try Parser.init(gpa, self.text);
    const ast = try parser.parse();
    var ast_tracked = false;
    errdefer if (!ast_tracked) ast.deinit(gpa);

    try gc.track(ast);
    ast_tracked = true;

    return evaluate(ast, gc, env);
}

const testing = std.testing;
const print = std.debug.print;
const scripts_dir = "examples/";

test "run all example scripts" {
    const gpa = testing.allocator;

    var dir = try fs.cwd().openDir(scripts_dir, .{ .iterate = true });
    defer dir.close();

    var files = dir.iterate();
    var ntotal: usize = 0;
    var npass: usize = 0;
    var nfail: usize = 0;

    var passed: ArrayList([]u8) = .empty;
    defer {
        for (passed.items) |item| gpa.free(item);
        passed.deinit(gpa);
    }

    var failed: ArrayList(struct { name: []u8, err: anyerror }) = .empty;
    defer {
        for (failed.items) |item| gpa.free(item.name);
        failed.deinit(gpa);
    }

    while (try files.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".lx")) continue;

        ntotal += 1;

        const path = try std.fs.path.join(gpa, &.{ scripts_dir, entry.name });
        defer gpa.free(path);

        var script = try Script.init(gpa, path);
        defer script.deinit();

        _ = script.run(null) catch |err| {
            try failed.append(gpa, .{
                .name = try gpa.dupe(u8, entry.name),
                .err = err,
            });
            nfail += 1;
            continue;
        };

        try passed.append(gpa, try gpa.dupe(u8, entry.name));
        npass += 1;
    }

    for (passed.items) |name| {
        print("{s}PASS{s}  {s}\n", .{ ansi.green, ansi.reset, name });
    }

    for (failed.items) |item| {
        print("{s}FAIL{s}  {s}  {s}{t}{s}\n", .{
            ansi.red,
            ansi.reset,
            item.name,
            ansi.red,
            item.err,
            ansi.reset,
        });
    }
}
