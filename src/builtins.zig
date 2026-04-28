const std = @import("std");

const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const Value = @import("value.zig").Value;
const NativeContext = Value.NativeContext;

const NativeFn = *const fn (context: NativeContext, argument: Value) anyerror!Value;

const Builtin = struct {
    name: []const u8,
    field_name: []const u8,
    function: NativeFn,
};

const record_builtins = [_]Builtin{
    .{ .name = "record.has", .field_name = "has", .function = recordHasBuiltin },
    .{ .name = "record.put", .field_name = "put", .function = recordPutBuiltin },
    .{ .name = "record.remove", .field_name = "remove", .function = recordRemoveBuiltin },
    .{ .name = "record.entries", .field_name = "entries", .function = recordEntriesBuiltin },
};

const list_builtins = [_]Builtin{
    .{ .name = "list.size", .field_name = "size", .function = listSizeBuiltin },
    .{ .name = "list.entries", .field_name = "entries", .function = listEntriesBuiltin },
};

const tuple_builtins = [_]Builtin{
    .{ .name = "tuple.size", .field_name = "size", .function = tupleSizeBuiltin },
    .{ .name = "tuple.entries", .field_name = "entries", .function = tupleEntriesBuiltin },
};

const string_builtins = [_]Builtin{
    .{ .name = "string.size", .field_name = "size", .function = stringSizeBuiltin },
};

const pretty_builtins = [_]Builtin{
    .{ .name = "pretty.print", .field_name = "print", .function = prettyPrintBuiltin },
    .{ .name = "pretty.show", .field_name = "show", .function = prettyShowBuiltin },
};

pub fn install(gc: *Gc, env: *Environment) !void {
    try buildIn(gc, env, "print", printBuiltin);
    try buildIn(gc, env, "exit", exitBuiltin);
    try installNamespace(gc, env, "record", &record_builtins);
    try installNamespace(gc, env, "list", &list_builtins);
    try installNamespace(gc, env, "tuple", &tuple_builtins);
    try installNamespace(gc, env, "string", &string_builtins);
    try installNamespace(gc, env, "pretty", &pretty_builtins);
}

fn buildIn(
    gc: *Gc,
    env: *Environment,
    name: []const u8,
    function: NativeFn,
) !void {
    const value = try installNative(gc, name, function);
    try env.bind(name, value);
}

fn installNative(
    gc: *Gc,
    name: []const u8,
    function: NativeFn,
) !Value {
    const value = try Value.Native.init(gc.allocator(), name, function);
    try gc.track(value);
    return value;
}

fn installNamespace(gc: *Gc, env: *Environment, name: []const u8, builtins: []const Builtin) !void {
    const entries = try gc.allocator().alloc(Value.Map.Entry, builtins.len);
    errdefer gc.allocator().free(entries);

    for (builtins, 0..) |builtin, index| {
        const function = try installNative(gc, builtin.name, builtin.function);
        const key = try Value.String.init(gc.allocator(), builtin.field_name);
        try gc.track(key);
        entries[index] = .{ .key = key, .value = function };
    }

    const namespace = try Value.Map.initOwned(gc.allocator(), entries);
    try gc.track(namespace);
    try env.bind(name, namespace);
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
    const status = switch (argument) {
        .unit => 0,
        .integer => |integer| integer,
        else => return error.TypeError,
    };
    std.process.exit(@intCast(status));
}

fn prettyPrintBuiltin(context: NativeContext, argument: Value) !Value {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(context.io, &buffer);
    const term: std.Io.Terminal = .{
        .writer = &stdout_writer.interface,
        .mode = std.Io.Terminal.Mode.detect(context.io, stdout_writer.file, false, false) catch .no_color,
    };
    try argument.writePrettyTerminal(term);
    try stdout_writer.interface.writeByte('\n');
    try stdout_writer.interface.flush();
    return .{ .unit = {} };
}

fn prettyShowBuiltin(context: NativeContext, argument: Value) !Value {
    var out = std.Io.Writer.Allocating.init(context.allocator());
    errdefer out.deinit();

    try argument.writePretty(&out.writer);
    const bytes = try out.toOwnedSlice();
    errdefer context.allocator().free(bytes);

    const value = try Value.String.initOwned(context.allocator(), bytes);
    try context.track(value);
    return value;
}

fn recordHasBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const args = try expectTuple(argument, 2);
    const map = args[0].asMap() orelse return error.TypeError;
    const key = args[1].asString() orelse return error.TypeError;
    return .{ .boolean = map.findStringIndex(key) != null };
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

fn listSizeBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const list = argument.asList() orelse return error.TypeError;
    return integerFromLen(list.items.len);
}

fn listEntriesBuiltin(context: NativeContext, argument: Value) !Value {
    const list = argument.asList() orelse return error.TypeError;
    return indexedEntries(context, list.items);
}

fn tupleSizeBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const tuple = argument.asTuple() orelse return error.TypeError;
    return integerFromLen(tuple.items.len);
}

fn tupleEntriesBuiltin(context: NativeContext, argument: Value) !Value {
    const tuple = argument.asTuple() orelse return error.TypeError;
    return indexedEntries(context, tuple.items);
}

fn stringSizeBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const bytes = argument.asString() orelse return error.TypeError;
    return integerFromLen(bytes.len);
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

fn indexedEntries(context: NativeContext, values: []const Value) !Value {
    _ = try integerFromLen(values.len);
    const items = try context.allocator().alloc(Value, values.len);
    errdefer context.allocator().free(items);

    for (values, 0..) |value, index| {
        const tuple_items = try context.allocator().alloc(Value, 2);
        errdefer context.allocator().free(tuple_items);

        tuple_items[0] = .{ .integer = @intCast(index) };
        tuple_items[1] = value;

        const tuple = try Value.Tuple.initOwned(context.allocator(), tuple_items);
        try context.track(tuple);
        items[index] = tuple;
    }

    const result = try Value.List.initOwned(context.allocator(), items);
    try context.track(result);
    return result;
}

fn integerFromLen(len: usize) !Value {
    if (len > @as(usize, @intCast(std.math.maxInt(i64)))) return error.IntegerOverflow;
    return .{ .integer = @intCast(len) };
}
