const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const fs = std.fs;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const evaluate = @import("evaluate.zig").evaluate;
const Parser = @import("Parser.zig");
const Value = @import("value.zig").Value;
const Object = @import("object.zig").Object;

const max_file_size = std.math.maxInt(u32);
const Script = @This();

gpa: Allocator,
objects: ArrayList(Object) = .empty,
path: []u8,
text: []u8,

pub fn init(gpa: Allocator, path: []const u8) !Script {
    const text = try fs.cwd().readFileAlloc(gpa, path, max_file_size);
    const copy = try gpa.dupe(u8, path);
    return Script{
        .gpa = gpa,
        .path = copy,
        .text = text,
        .objects = .empty,
    };
}

pub fn deinit(self: *Script) void {
    for (self.objects.items) |*object| object.deinit(self.gpa);
    self.objects.deinit(self.gpa);
    self.gpa.free(self.text);
    self.gpa.free(self.path);
}

pub fn run(self: *Script, parent_env: ?*Environment) !Value {
    const gpa = self.gpa;

    var env = try Environment.init(gpa, parent_env);
    try self.objects.append(gpa, Object{ .env = env });

    const exit = @import("builtin/exit.zig");
    try env.define(exit.name, Value.Builtin.init(exit.name, exit.function, null));

    var parser = try Parser.init(gpa, self.text);
    const ast = try parser.parse();
    defer ast.deinit(gpa);

    return evaluate(gpa, ast, env, &self.objects);
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
