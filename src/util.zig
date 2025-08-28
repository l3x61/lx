const std = @import("std");
const time = std.time;
const ns_per_us = time.ns_per_us;
const ns_per_ms = time.ns_per_ms;
const ns_per_s = time.ns_per_s;

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
            break :block std.fmt.bufPrint(buffer, "{d:.6}s", .{s});
        },
    };
}
