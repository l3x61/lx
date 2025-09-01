const std = @import("std");
const Allocator = std.mem.Allocator;
const DebugAllocator = std.heap.DebugAllocator;
const print = std.debug.print;

const exit = std.process.exit;

const fs = std.fs;

const maxInt = std.math.maxInt;

const mem = std.mem;
const sort = mem.sort;
const endsWith = mem.endsWith;

const lx = @import("lx");
const ansi = lx.ansi;
const Script = lx.Script;

pub const std_options = std.Options{
    .logFn = logFn,
};

fn logFn(
    comptime _: std.log.Level,
    comptime _: @TypeOf(.enum_literal),
    comptime _: []const u8,
    _: anytype,
) void {}

pub fn main() !void {
    var da: DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const gpa = da.allocator();

    var result = Result{};
    defer result.deinit(gpa);

    try runTests(gpa, "spec/pass", .should_pass, &result);
    try runTests(gpa, "spec/fail", .should_fail, &result);

    sort([]const u8, result.passed_paths.items, {}, lessThanU8);
    sort([]const u8, result.failed_paths.items, {}, lessThanU8);

    for (result.passed_paths.items) |path| {
        print("{s}PASS{s}  {s}\n", .{ ansi.green, ansi.reset, path });
    }
    for (result.failed_paths.items) |path| {
        print("{s}FAIL{s}  {s}\n", .{ ansi.red, ansi.reset, path });
    }

    switch (result.failed) {
        0 => print(
            "\nAll {d} tests passed\n",
            .{result.total},
        ),
        else => print("\n{d} test{s} failed out of {d}\n", .{
            result.failed,
            if (result.failed == 1) "" else "s",
            result.total,
        }),
    }

    if (result.failed != 0) exit(1);
}

const Mode = enum { should_pass, should_fail };

const Result = struct {
    total: usize = 0,
    failed: usize = 0,
    passed_paths: std.ArrayList([]const u8) = .empty,
    failed_paths: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *Result, gpa: Allocator) void {
        for (self.passed_paths.items) |p| gpa.free(p);
        self.passed_paths.deinit(gpa);
        for (self.failed_paths.items) |p| gpa.free(p);
        self.failed_paths.deinit(gpa);
    }
};

fn lessThanU8(_: void, a: []const u8, b: []const u8) bool {
    return mem.lessThan(u8, a, b);
}

fn runTests(gpa: Allocator, dir_path: []const u8, mode: Mode, result: *Result) !void {
    var dir = try fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var script_paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (script_paths.items) |script_path| gpa.free(script_path);
        script_paths.deinit(gpa);
    }

    var files = dir.iterate();
    while (try files.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!endsWith(u8, entry.name, ".lx")) continue;

        const script_path = try fs.path.join(gpa, &.{ dir_path, entry.name });
        try script_paths.append(gpa, script_path);
    }

    sort([]const u8, script_paths.items, {}, lessThanU8);

    for (script_paths.items) |script_path| {
        result.total += 1;

        var failed = false;
        {
            var script = Script.init(gpa, script_path) catch {
                failed = true;
                continue;
            };
            defer script.deinit();

            var run_result = script.run(null) catch {
                failed = true;
                continue;
            };
            run_result.deinit(gpa);
        }

        if (!failed != (mode == .should_pass)) {
            result.failed += 1;
            try result.failed_paths.append(gpa, try gpa.dupe(u8, script_path));
        } else {
            try result.passed_paths.append(gpa, try gpa.dupe(u8, script_path));
        }
    }
}
