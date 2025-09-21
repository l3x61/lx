const std = @import("std");
const build_options = @import("build_options");

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
const Gc = @import("Gc.zig");

const Repl = @This();
const prompt = ansi.cyan ++ "> " ++ ansi.reset;

gpa: Allocator,
gc: Gc,
env: *Environment,
rl: ReadLine,

var stdout_buffer: [max_path_bytes]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var stderr_buffer: [max_path_bytes]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
const stderr = &stderr_writer.interface;

const result_name = "?";

fn initEnv(gc: *Gc) !*Environment {
    const exit = @import("native/exit.zig");

    const gpa = gc.allocator();

    var env_tracked = false;
    var env = try Environment.init(gpa, null);
    errdefer if (!env_tracked) env.deinit();

    try gc.track(env);
    env_tracked = true;

    try env.bind(result_name, Value.init());

    var native_tracked = false;
    var native = try Value.Native.init(gpa, exit.name, exit.function, null);
    errdefer if (!native_tracked) native.deinit(gpa);
    try env.bind(exit.name, native);
    try gc.track(native);
    native_tracked = true;

    return env;
}

pub fn init(gpa: Allocator) !Repl {
    var gc = try Gc.init(gpa);
    errdefer gc.deinit();

    const env = try initEnv(&gc);

    return Repl{
        .gpa = gpa,
        .gc = gc,
        .env = env,
        .rl = ReadLine.init(gpa, stdout),
    };
}

pub fn deinit(self: *Repl) void {
    self.gc.deinit();
    self.rl.deinit();
}

pub fn run(self: *Repl) !void {
    const gpa = self.gpa;
    const gc = &self.gc;
    const gc_gpa = gc.allocator();
    const env = self.env;
    var rl = &self.rl;

    try welcomeMessage();

    var timer = try Timer.start();

    while (true) {
        const input = rl.readLine(prompt) catch |err| switch (err) {
            error.Interrupted => break,
            else => return err,
        };
        defer gpa.free(input);

        var line_tracked = false;
        var line = try Value.String.init(gpa, input);
        errdefer if (!line_tracked) line.deinit(gc_gpa);

        try gc.track(line);
        line_tracked = true;

        _ = timer.lap();

        var parser = try Parser.init(gc_gpa, line.asString().?);

        var ast_tracked = false;
        const ast = parser.parse() catch continue;
        errdefer if (!ast_tracked) ast.deinit(gc_gpa);

        try gc.track(ast);
        ast_tracked = true;

        const parse_duration = timer.lap();

        const result = evaluate(ast, gc, env) catch continue;
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
