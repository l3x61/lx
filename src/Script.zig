const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const fs = std.fs;

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
    try env.define(gpa, exit.name, Value.Builtin.init(exit.name, exit.function, null));

    var parser = try Parser.init(gpa, self.text);
    const ast = try parser.parse();
    defer ast.deinit(gpa);

    return evaluate(gpa, ast, env, &self.objects);
}
