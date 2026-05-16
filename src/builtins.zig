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
    .{ .name = "record.entries", .field_name = "entries", .function = recordEntriesBuiltin },
};

const list_builtins = [_]Builtin{
    .{ .name = "list.size", .field_name = "size", .function = listSizeBuiltin },
};

const tuple_builtins = [_]Builtin{
    .{ .name = "tuple.size", .field_name = "size", .function = tupleSizeBuiltin },
};

const string_builtins = [_]Builtin{
    .{ .name = "string.size", .field_name = "size", .function = stringSizeBuiltin },
};

const pretty_builtins = [_]Builtin{
    .{ .name = "pretty.print", .field_name = "print", .function = prettyPrintBuiltin },
    .{ .name = "pretty.show", .field_name = "show", .function = prettyShowBuiltin },
};

pub fn install(gc: *Gc, env: *Environment) !void {
    try installBuiltin(gc, env, "print", printBuiltin);
    try installNamespace(gc, env, "record", &record_builtins);
    try installNamespace(gc, env, "list", &list_builtins);
    try installNamespace(gc, env, "tuple", &tuple_builtins);
    try installNamespace(gc, env, "string", &string_builtins);
    try installNamespace(gc, env, "pretty", &pretty_builtins);
}

fn installBuiltin(
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
    const entries = try gc.allocator().alloc(Value.Record.Entry, builtins.len);
    errdefer gc.allocator().free(entries);

    for (builtins, 0..) |builtin, index| {
        const function = try installNative(gc, builtin.name, builtin.function);
        entries[index] = .{ .key = builtin.field_name, .value = function };
    }

    const namespace = try Value.Record.initOwned(gc.allocator(), entries);
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

fn recordEntriesBuiltin(context: NativeContext, argument: Value) !Value {
    const record = argument.asRecord() orelse return error.TypeError;
    const items = try context.allocator().alloc(Value, record.entries.len);
    errdefer context.allocator().free(items);

    for (record.entries, 0..) |entry, index| {
        const tuple_items = try context.allocator().alloc(Value, 2);
        errdefer context.allocator().free(tuple_items);

        const key_value = try Value.String.init(context.allocator(), entry.key);
        try context.track(key_value);

        tuple_items[0] = key_value;
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

fn tupleSizeBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const tuple = argument.asTuple() orelse return error.TypeError;
    return integerFromLen(tuple.items.len);
}

fn stringSizeBuiltin(context: NativeContext, argument: Value) !Value {
    _ = context;
    const bytes = argument.asString() orelse return error.TypeError;
    return integerFromLen(bytes.len);
}

fn integerFromLen(len: usize) !Value {
    if (len > @as(usize, @intCast(std.math.maxInt(i64)))) return error.IntegerOverflow;
    return .{ .integer = @intCast(len) };
}
