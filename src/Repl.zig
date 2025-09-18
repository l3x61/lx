const std = @import("std");
const build_options = @import("build_options");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.repl);
const max_path_bytes = std.fs.max_path_bytes;

const time = std.time;
const Timer = time.Timer;
const ns_per_us = time.ns_per_us;
const ns_per_ms = time.ns_per_ms;
const ns_per_s = time.ns_per_s;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const evaluate = @import("evaluate.zig").evaluate;
const Lexer = @import("Lexer.zig");
const Parser = @import("Parser.zig");
const ReadLine = @import("readline.zig");
const Value = @import("value.zig").Value;
const Object = @import("object.zig").Object;

const Repl = @This();
const prompt = ansi.cyan ++ "> " ++ ansi.reset;

gpa: Allocator,
env: *Environment,
rl: ReadLine,
objects: ArrayList(Object),

var stdout_buffer: [max_path_bytes]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var stderr_buffer: [max_path_bytes]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
const stderr = &stderr_writer.interface;

const result_name = "?";

fn initEnv(gpa: Allocator) !*Environment {
    const exit = @import("native/exit.zig");

    var env = try Environment.init(gpa, null);
    try env.bind(result_name, Value.init());
    try env.bind(exit.name, try Value.Native.init(gpa, exit.name, exit.function, null));

    return env;
}

pub fn init(gpa: Allocator) !Repl {
    var objects: ArrayList(Object) = .empty;
    const env = try initEnv(gpa);
    try objects.append(gpa, Object{ .env = env });

    return Repl{
        .gpa = gpa,
        .env = env,
        .rl = ReadLine.init(gpa, stdout),
        .objects = objects,
    };
}

pub fn deinit(self: *Repl) void {
    for (self.objects.items) |*item| {
        item.deinit(self.gpa);
    }
    self.objects.deinit(self.gpa);

    self.rl.deinit();
}

pub fn run(self: *Repl) !void {
    const gpa = self.gpa;
    const env = self.env;
    var rl = &self.rl;
    const objects = &self.objects;

    try welcomeMessage();

    var timer = try Timer.start();

    while (true) {
        const line = rl.readLine(prompt) catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };
        const line_val = try Value.String.fromOwned(gpa, line);
        try objects.append(gpa, .{ .value = line_val });

        _ = timer.lap();

        var parser = try Parser.init(gpa, line);
        const ast = parser.parse() catch continue;
        try objects.append(gpa, .{ .node = ast });

        const parse_duration = timer.lap();

        const result = evaluate(gpa, ast, env, objects) catch continue;
        try env.set(result_name, result);

        const exec_duration = timer.read();

        log.info("parsing   {s}\n", .{try formatElapsedTime(&stdout_buffer, parse_duration)});
        log.info("executing {s}\n", .{try formatElapsedTime(&stdout_buffer, exec_duration)});
        log.info("total     {s}\n", .{try formatElapsedTime(&stdout_buffer, parse_duration + exec_duration)});

        try stdout.print(ansi.bold ++ "{f}\n\n" ++ ansi.reset, .{result});
        try stdout.flush();
    }
}

fn welcomeMessage() !void {
    try stderr.print("{s}λ{s}x{s}.{s} version {s}\n", .{
        ansi.bold ++ ansi.red,
        ansi.reset ++ ansi.bold,
        ansi.red,
        ansi.reset,
        build_options.version,
    });
    // TODO: provide a `help` command
    try stderr.flush();
}

pub fn formatElapsedTime(buffer: []u8, ns: u64) ![]const u8 {
    return switch (ns) {
        0...ns_per_us - 1 => try std.fmt.bufPrint(buffer, "{}ns", .{ns}),

        ns_per_us...ns_per_ms - 1 => block: {
            const us = @as(f64, @floatFromInt(ns)) / std.time.ns_per_us;
            break :block std.fmt.bufPrint(buffer, "{d:.2}μs", .{us});
        },

        ns_per_ms...ns_per_s - 1 => block: {
            const ms = @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
            break :block try std.fmt.bufPrint(buffer, "{d:.3}ms", .{ms});
        },

        else => block: {
            const s = @as(f64, @floatFromInt(ns)) / std.time.ns_per_s;
            break :block try std.fmt.bufPrint(buffer, "{d:.6}s", .{s});
        },
    };
}
