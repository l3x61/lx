const std = @import("std");

const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const Value = @import("value.zig").Value;
const NativeContext = Value.NativeContext;

pub fn install(gc: *Gc, env: *Environment) !void {
    try buildIn(gc, env, "print", printBuiltin);
    try buildIn(gc, env, "exit", exitBuiltin);
    try buildIn(gc, env, "record_has", recordHasBuiltin);
    try buildIn(gc, env, "record_get", recordGetBuiltin);
    try buildIn(gc, env, "record_get_or", recordGetOrBuiltin);
    try buildIn(gc, env, "record_put", recordPutBuiltin);
    try buildIn(gc, env, "record_remove", recordRemoveBuiltin);
    try buildIn(gc, env, "record_entries", recordEntriesBuiltin);
    try buildIn(gc, env, "record_size", recordSizeBuiltin);
}

fn buildIn(
    gc: *Gc,
    env: *Environment,
    name: []const u8,
    function: *const fn (context: NativeContext, argument: Value) anyerror!Value,
) !void {
    const value = try Value.Native.init(gc.allocator(), name, function);
    try gc.track(value);
    try env.bind(name, value);
}

fn printBuiltin(context: NativeContext, argument: Value) !Value {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(context.io, &buffer);
    try argument.display(&stdout_writer.interface);
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.interface.flush();
    return .{ .unit = {} };
}

fn exitBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const status = argument.asInteger() orelse return error.TypeError;
    std.process.exit(@intCast(status));
}

fn recordHasBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const args = try expectTuple(argument, 2);
    const map = args[0].asMap() orelse return error.TypeError;
    const key = args[1].asString() orelse return error.TypeError;
    return .{ .boolean = map.findStringIndex(key) != null };
}

fn recordGetBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const args = try expectTuple(argument, 2);
    const map = args[0].asMap() orelse return error.TypeError;
    const key = args[1].asString() orelse return error.TypeError;
    const index = map.findStringIndex(key) orelse return error.KeyNotFound;
    return map.entries[index].value;
}

fn recordGetOrBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const args = try expectTuple(argument, 3);
    const map = args[0].asMap() orelse return error.TypeError;
    const key = args[1].asString() orelse return error.TypeError;
    const index = map.findStringIndex(key) orelse return args[2];
    return map.entries[index].value;
}

fn recordPutBuiltin(context: NativeContext, argument: Value) !Value {
    const args = try expectTuple(argument, 3);
    const map = args[0].asMap() orelse return error.TypeError;
    _ = args[1].asString() orelse return error.TypeError;
    return copyMapWithEntry(context, map, args[1], args[2]);
}

fn recordRemoveBuiltin(context: NativeContext, argument: Value) !Value {
    const args = try expectTuple(argument, 2);
    const map = args[0].asMap() orelse return error.TypeError;
    const key = args[1].asString() orelse return error.TypeError;
    const remove_index = map.findStringIndex(key) orelse return args[0];

    const entries = try context.allocator().alloc(Value.Map.Entry, map.entries.len - 1);
    errdefer context.allocator().free(entries);

    var out_index: usize = 0;
    for (map.entries, 0..) |entry, index| {
        if (index == remove_index) continue;
        entries[out_index] = entry;
        out_index += 1;
    }

    const value = try Value.Map.initOwned(context.allocator(), entries);
    try context.track(value);
    return value;
}

fn recordEntriesBuiltin(context: NativeContext, argument: Value) !Value {
    const map = argument.asMap() orelse return error.TypeError;
    const items = try context.allocator().alloc(Value, map.entries.len);
    errdefer context.allocator().free(items);

    for (map.entries, 0..) |entry, index| {
        const tuple_items = try context.allocator().alloc(Value, 2);
        errdefer context.allocator().free(tuple_items);

        tuple_items[0] = entry.key;
        tuple_items[1] = entry.value;

        const tuple = try Value.Tuple.initOwned(context.allocator(), tuple_items);
        try context.track(tuple);
        items[index] = tuple;
    }

    const value = try Value.List.initOwned(context.allocator(), items);
    try context.track(value);
    return value;
}

fn recordSizeBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const map = argument.asMap() orelse return error.TypeError;
    if (map.entries.len > @as(usize, @intCast(std.math.maxInt(i64)))) return error.IntegerOverflow;
    return .{ .integer = @intCast(map.entries.len) };
}

fn expectTuple(argument: Value, len: usize) ![]Value {
    const tuple = argument.asTuple() orelse return error.TypeError;
    if (tuple.items.len != len) return error.TypeError;
    return tuple.items;
}

fn copyMapWithEntry(
    context: NativeContext,
    map: *Value.Map,
    key: Value,
    value: Value,
) !Value {
    const key_bytes = key.asString() orelse return error.TypeError;
    const existing = map.findStringIndex(key_bytes);
    const len = if (existing == null) map.entries.len + 1 else map.entries.len;
    const entries = try context.allocator().alloc(Value.Map.Entry, len);
    errdefer context.allocator().free(entries);

    @memcpy(entries[0..map.entries.len], map.entries);
    if (existing) |index| {
        entries[index].value = value;
    } else {
        entries[map.entries.len] = .{ .key = key, .value = value };
    }

    const result = try Value.Map.initOwned(context.allocator(), entries);
    try context.track(result);
    return result;
}
