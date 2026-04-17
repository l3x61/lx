const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Runtime = @import("Runtime.zig");
const Value = @import("value.zig").Value;

const Script = @This();

gpa: Allocator,
io: Io,
runtime: Runtime,
path: []u8,
text: []u8,

pub fn init(gpa: Allocator, io: Io, path: []const u8) !Script {
    const runtime = try Runtime.init(gpa, io);
    errdefer {
        var owned_runtime = runtime;
        owned_runtime.deinit();
    }

    const owned_path = try gpa.dupe(u8, path);
    errdefer gpa.free(owned_path);

    const text = try Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
    errdefer gpa.free(text);

    return .{
        .gpa = gpa,
        .io = io,
        .runtime = runtime,
        .path = owned_path,
        .text = text,
    };
}

pub fn deinit(self: *Script) void {
    self.runtime.deinit();
    self.gpa.free(self.path);
    self.gpa.free(self.text);
}

pub fn run(self: *Script) !Value {
    return self.runtime.evaluateSource(self.text);
}

const testing = std.testing;

test "runs current non-print examples" {
    const files = [_][]const u8{
        "examples/abs.lx",
        "examples/block.lx",
        "examples/classify.lx",
        "examples/head.lx",
        "examples/lists-and-ranges.lx",
    };

    for (files) |path| {
        var script = try Script.init(testing.allocator, testing.io, path);
        defer script.deinit();
        _ = try script.run();
    }
}
