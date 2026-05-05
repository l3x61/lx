const std = @import("std");
const Allocator = std.mem.Allocator;
const parseInt = std.fmt.parseInt;

const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const node_mod = @import("node.zig");
const Node = node_mod.Node;
const Clause = node_mod.Clause;
const Pattern = node_mod.Pattern;
const Rest = node_mod.Rest;
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;

pub const EvalError = error{
    UnboundName,
    UninitializedRecursiveBinding,
    TypeError,
    DivideByZero,
    IndexOutOfBounds,
    KeyNotFound,
    ApplyNonFunction,
    NoMatch,
    InvalidStringLiteral,
    IntegerOverflow,
    OutOfMemory,
};

pub fn evaluate(node: *Node, gc: *Gc, env: *Environment) anyerror!Value {
    return evalNode(node, gc, env);
}

fn evalNode(node: *Node, gc: *Gc, env: *Environment) anyerror!Value {
    return switch (node.*) {
        .program => |program| evalNode(program.expression, gc, env),
        .identifier => |token| env.get(token.lexeme) catch |err| switch (err) {
            error.NotDefined => error.UnboundName,
            error.UninitializedBinding => error.UninitializedRecursiveBinding,
        },
        .literal => |token| evalLiteral(token, gc),
        .unary => |unary| evalUnary(unary, gc, env),
        .binary => |binary| evalBinary(binary, gc, env),
        .application => |app| evalApplication(app, gc, env),
        .index => |idx| evalIndex(idx, gc, env),
        .list => |list| evalList(list, gc, env),
        .tuple => |tuple| evalTuple(tuple, gc, env),
        .map => |map| evalMap(map, gc, env),
        .function => |function| evalFunction(function, gc, env),
        .binding => |binding| evalBinding(binding, gc, env),
    };
}

fn evalLiteral(token: Token, gc: *Gc) anyerror!Value {
    return switch (token.tag) {
        .unit => .{ .unit = {} },
        .true => .{ .boolean = true },
        .false => .{ .boolean = false },
        .integer => .{ .integer = try parseInteger(token.lexeme) },
        .string => blk: {
            const decoded = try decodeStringLiteral(gc.allocator(), token.lexeme);
            errdefer gc.allocator().free(decoded);
            const value = try Value.String.initOwned(gc.allocator(), decoded);
            try gc.track(value);
            break :blk value;
        },
        else => unreachable,
    };
}

fn evalUnary(unary: Node.Unary, gc: *Gc, env: *Environment) anyerror!Value {
    const operand = try evalNode(unary.operand, gc, env);
    return switch (unary.operator.tag) {
        .minus => .{ .integer = std.math.negate(operand.asInteger() orelse return error.TypeError) catch return error.IntegerOverflow },
        .not => .{ .boolean = !(operand.asBoolean() orelse return error.TypeError) },
        else => unreachable,
    };
}

fn evalBinary(binary: Node.Binary, gc: *Gc, env: *Environment) anyerror!Value {
    const left = try evalNode(binary.left, gc, env);
    const right = try evalNode(binary.right, gc, env);

    return switch (binary.operator.tag) {
        .equal => .{ .boolean = left.equal(right) },
        .not_equal => .{ .boolean = !left.equal(right) },
        .greater => compareIntegers(left, right, .greater),
        .greater_equal => compareIntegers(left, right, .greater_equal),
        .less => compareIntegers(left, right, .less),
        .less_equal => compareIntegers(left, right, .less_equal),
        .plus => arithmetic(left, right, .plus),
        .minus => arithmetic(left, right, .minus),
        .star => arithmetic(left, right, .star),
        .slash => arithmetic(left, right, .slash),
        .percent => arithmetic(left, right, .percent),
        .concat => concatValues(left, right, gc),
        .cons => consValue(left, right, gc),
        .and_and => {
            const l = left.asBoolean() orelse return error.TypeError;
            const r = right.asBoolean() orelse return error.TypeError;
            return .{ .boolean = l and r };
        },
        .or_or => {
            const l = left.asBoolean() orelse return error.TypeError;
            const r = right.asBoolean() orelse return error.TypeError;
            return .{ .boolean = l or r };
        },
        else => unreachable,
    };
}

fn evalApplication(app: Node.Application, gc: *Gc, env: *Environment) anyerror!Value {
    const callee = try evalNode(app.callee, gc, env);
    const argument = try evalNode(app.argument, gc, env);
    return applyValue(callee, argument, gc);
}

fn applyValue(callee: Value, argument: Value, gc: *Gc) anyerror!Value {
    if (callee.asNative()) |native| return native.function(gc.nativeContext(), argument);

    const closure = callee.asClosure() orelse return error.ApplyNonFunction;
    for (closure.clauses) |clause| {
        const scope = try Environment.init(gc.allocator(), closure.env);
        var keep = false;
        defer if (!keep) scope.deinit();

        if (try tryMatchPattern(clause.pattern, argument, scope, gc)) {
            try gc.track(scope);
            keep = true;
            return evalNode(clause.body, gc, scope);
        }
    }
    return error.NoMatch;
}

fn evalIndex(idx: Node.Index, gc: *Gc, env: *Environment) anyerror!Value {
    const target = try evalNode(idx.target, gc, env);
    const key = try evalNode(idx.index, gc, env);

    if (target.asMap()) |map| {
        const key_bytes = key.asString() orelse return error.TypeError;
        const entry_index = map.findStringIndex(key_bytes) orelse return error.KeyNotFound;
        return map.entries[entry_index].value;
    }

    const i = key.asInteger() orelse return error.TypeError;
    if (i < 0) return error.IndexOutOfBounds;
    const u: usize = @intCast(i);

    if (target.asList()) |list| {
        if (u >= list.items.len) return error.IndexOutOfBounds;
        return list.items[u];
    }
    if (target.asTuple()) |tuple| {
        if (u >= tuple.items.len) return error.IndexOutOfBounds;
        return tuple.items[u];
    }
    if (target.asString()) |bytes| {
        if (u >= bytes.len) return error.IndexOutOfBounds;
        return .{ .integer = @intCast(bytes[u]) };
    }
    return error.TypeError;
}

fn evalList(list: Node.List, gc: *Gc, env: *Environment) anyerror!Value {
    var items: std.ArrayList(Value) = .empty;
    errdefer items.deinit(gc.allocator());
    for (list.items) |item| {
        try items.append(gc.allocator(), try evalNode(item, gc, env));
    }
    const owned = try items.toOwnedSlice(gc.allocator());
    errdefer gc.allocator().free(owned);
    const value = try Value.List.initOwned(gc.allocator(), owned);
    try gc.track(value);
    return value;
}

fn evalMap(map: Node.Map, gc: *Gc, env: *Environment) anyerror!Value {
    var entries: std.ArrayList(Value.Map.Entry) = .empty;
    errdefer entries.deinit(gc.allocator());

    for (map.entries) |entry| {
        const key = try Value.String.init(gc.allocator(), entry.key);
        try gc.track(key);
        const value = try evalNode(entry.value, gc, env);
        try putMapEntryInList(&entries, gc.allocator(), key, value);
    }

    const owned = try entries.toOwnedSlice(gc.allocator());
    errdefer gc.allocator().free(owned);
    const value = try Value.Map.initOwned(gc.allocator(), owned);
    try gc.track(value);
    return value;
}

fn evalTuple(tuple: Node.Tuple, gc: *Gc, env: *Environment) anyerror!Value {
    var items: std.ArrayList(Value) = .empty;
    errdefer items.deinit(gc.allocator());
    for (tuple.items) |item| {
        try items.append(gc.allocator(), try evalNode(item, gc, env));
    }
    const owned = try items.toOwnedSlice(gc.allocator());
    errdefer gc.allocator().free(owned);
    const value = try Value.Tuple.initOwned(gc.allocator(), owned);
    try gc.track(value);
    return value;
}

fn evalFunction(function: Node.Function, gc: *Gc, env: *Environment) anyerror!Value {
    const value = try Value.Closure.init(gc.allocator(), function.clauses, env);
    try gc.track(value);
    return value;
}

fn evalBinding(binding: Node.Binding, gc: *Gc, env: *Environment) anyerror!Value {
    const scope = try Environment.init(gc.allocator(), env);
    var keep = false;
    errdefer if (!keep) scope.deinit();

    try preallocatePatternCells(binding.pattern, scope);

    const value = try evalNode(binding.value, gc, scope);
    if (!try tryMatchPattern(binding.pattern, value, scope, gc)) {
        return error.NoMatch;
    }

    try gc.track(scope);
    keep = true;
    return evalNode(binding.body, gc, scope);
}

fn preallocatePatternCells(pattern: *Pattern, env: *Environment) anyerror!void {
    switch (pattern.*) {
        .wildcard, .literal => {},
        .identifier => |token| {
            env.bind(token.lexeme, null) catch |err| switch (err) {
                error.AlreadyDefined => {},
                else => return err,
            };
        },
        .tuple => |tuple| {
            for (tuple.items) |p| try preallocatePatternCells(p, env);
        },
        .list => |list| {
            for (list.items) |p| try preallocatePatternCells(p, env);
            switch (list.rest) {
                .pattern => |p| try preallocatePatternCells(p, env),
                else => {},
            }
        },
        .map => |map| {
            for (map.entries) |entry| try preallocatePatternCells(entry.pattern, env);
            switch (map.rest) {
                .pattern => |p| try preallocatePatternCells(p, env),
                else => {},
            }
        },
        .refinement => |r| try preallocatePatternCells(r.base, env),
        .alternative => |a| {
            try preallocatePatternCells(a.left, env);
            try preallocatePatternCells(a.right, env);
        },
    }
}

fn tryMatchPattern(pattern: *Pattern, value: Value, env: *Environment, gc: *Gc) anyerror!bool {
    return switch (pattern.*) {
        .wildcard => true,
        .identifier => |token| blk: {
            try bindOrSet(env, token.lexeme, value);
            break :blk true;
        },
        .literal => |lit| try literalMatches(lit, value, gc.allocator()),
        .tuple => |tuple| try matchTuplePattern(tuple.items, value, env, gc),
        .list => |list| try matchListPattern(list, value, env, gc),
        .map => |map| try matchMapPattern(map, value, env, gc),
        .refinement => |r| blk: {
            const mark = try env.snapshot();
            defer mark.deinit(env.gpa);

            if (!try tryMatchPattern(r.base, value, env, gc)) break :blk false;
            const cond = try evalNode(r.condition, gc, env);
            const b = cond.asBoolean() orelse return error.TypeError;
            if (!b) env.restore(mark);
            break :blk b;
        },
        .alternative => |a| blk: {
            const mark = try env.snapshot();
            defer mark.deinit(env.gpa);

            if (try tryMatchPattern(a.left, value, env, gc)) break :blk true;
            env.restore(mark);
            if (try tryMatchPattern(a.right, value, env, gc)) break :blk true;
            env.restore(mark);
            break :blk false;
        },
    };
}

fn bindOrSet(env: *Environment, name: []const u8, value: Value) !void {
    env.bind(name, value) catch |err| switch (err) {
        error.AlreadyDefined => try env.set(name, value),
        else => return err,
    };
}

fn matchTuplePattern(
    items: []const *Pattern,
    value: Value,
    env: *Environment,
    gc: *Gc,
) anyerror!bool {
    const tuple = value.asTuple() orelse return false;
    if (tuple.items.len != items.len) return false;
    const mark = try env.snapshot();
    defer mark.deinit(env.gpa);

    for (items, tuple.items) |p, v| {
        if (!try tryMatchPattern(p, v, env, gc)) {
            env.restore(mark);
            return false;
        }
    }
    return true;
}

fn matchListPattern(
    pattern: Pattern.ListPattern,
    value: Value,
    env: *Environment,
    gc: *Gc,
) anyerror!bool {
    const list = value.asList() orelse return false;
    const has_rest = switch (pattern.rest) {
        .none => false,
        else => true,
    };
    if (!has_rest and list.items.len != pattern.items.len) return false;
    if (has_rest and list.items.len < pattern.items.len) return false;
    const mark = try env.snapshot();
    defer mark.deinit(env.gpa);

    for (pattern.items, 0..) |p, i| {
        if (!try tryMatchPattern(p, list.items[i], env, gc)) {
            env.restore(mark);
            return false;
        }
    }

    switch (pattern.rest) {
        .none, .wildcard => {},
        .pattern => |p| {
            const suffix = list.items[pattern.items.len..];
            const tail = try Value.List.init(gc.allocator(), suffix);
            try gc.track(tail);
            if (!try tryMatchPattern(p, tail, env, gc)) {
                env.restore(mark);
                return false;
            }
        },
    }
    return true;
}

fn matchMapPattern(
    pattern: Pattern.MapPattern,
    value: Value,
    env: *Environment,
    gc: *Gc,
) anyerror!bool {
    const map = value.asMap() orelse return false;
    const has_rest = switch (pattern.rest) {
        .none => false,
        else => true,
    };
    if (!has_rest and map.entries.len != pattern.entries.len) return false;

    const mark = try env.snapshot();
    defer mark.deinit(env.gpa);

    for (pattern.entries) |entry| {
        const index = map.findStringIndex(entry.key) orelse {
            env.restore(mark);
            return false;
        };
        if (!try tryMatchPattern(entry.pattern, map.entries[index].value, env, gc)) {
            env.restore(mark);
            return false;
        }
    }

    switch (pattern.rest) {
        .none, .wildcard => {},
        .pattern => |rest_pattern| {
            const rest = try restMapForPattern(pattern.entries, map, gc);
            try gc.track(rest);
            if (!try tryMatchPattern(rest_pattern, rest, env, gc)) {
                env.restore(mark);
                return false;
            }
        },
    }

    return true;
}

fn restMapForPattern(
    pattern_entries: []const Pattern.MapPattern.Entry,
    map: *Value.Map,
    gc: *Gc,
) !Value {
    var rest_len: usize = 0;
    for (map.entries) |entry| {
        if (!mapKeyInPattern(pattern_entries, entry.key)) rest_len += 1;
    }

    const entries = try gc.allocator().alloc(Value.Map.Entry, rest_len);
    errdefer gc.allocator().free(entries);

    var out_index: usize = 0;
    for (map.entries) |entry| {
        if (mapKeyInPattern(pattern_entries, entry.key)) continue;
        entries[out_index] = entry;
        out_index += 1;
    }

    return Value.Map.initOwned(gc.allocator(), entries);
}

fn mapKeyInPattern(pattern_entries: []const Pattern.MapPattern.Entry, key: Value) bool {
    const bytes = key.asString() orelse return false;
    for (pattern_entries) |entry| {
        if (std.mem.eql(u8, entry.key, bytes)) return true;
    }
    return false;
}

const Comparison = enum { greater, greater_equal, less, less_equal };

fn compareIntegers(left: Value, right: Value, comparison: Comparison) anyerror!Value {
    const lhs = left.asInteger() orelse return error.TypeError;
    const rhs = right.asInteger() orelse return error.TypeError;
    return .{ .boolean = switch (comparison) {
        .greater => lhs > rhs,
        .greater_equal => lhs >= rhs,
        .less => lhs < rhs,
        .less_equal => lhs <= rhs,
    } };
}

const Arithmetic = enum { plus, minus, star, slash, percent };

fn arithmetic(left: Value, right: Value, op: Arithmetic) anyerror!Value {
    const lhs = left.asInteger() orelse return error.TypeError;
    const rhs = right.asInteger() orelse return error.TypeError;

    return switch (op) {
        .plus => .{ .integer = std.math.add(i64, lhs, rhs) catch return error.IntegerOverflow },
        .minus => .{ .integer = std.math.sub(i64, lhs, rhs) catch return error.IntegerOverflow },
        .star => .{ .integer = std.math.mul(i64, lhs, rhs) catch return error.IntegerOverflow },
        .slash => blk: {
            if (rhs == 0) return error.DivideByZero;
            const quotient = std.math.divTrunc(i64, lhs, rhs) catch |err| switch (err) {
                error.DivisionByZero => return error.DivideByZero,
                error.Overflow => return error.IntegerOverflow,
            };
            break :blk .{ .integer = quotient };
        },
        .percent => blk: {
            if (rhs == 0) return error.DivideByZero;
            if (lhs == std.math.minInt(i64) and rhs == -1) return error.IntegerOverflow;
            break :blk .{ .integer = @rem(lhs, rhs) };
        },
    };
}

fn parseInteger(lexeme: []const u8) anyerror!i64 {
    return parseInt(i64, lexeme, 10) catch |err| switch (err) {
        error.Overflow => error.IntegerOverflow,
        else => err,
    };
}

fn concatValues(left: Value, right: Value, gc: *Gc) anyerror!Value {
    if (left.asList()) |lhs| {
        const rhs = right.asList() orelse return error.TypeError;

        const items = try gc.allocator().alloc(Value, lhs.items.len + rhs.items.len);
        errdefer gc.allocator().free(items);

        @memcpy(items[0..lhs.items.len], lhs.items);
        @memcpy(items[lhs.items.len..], rhs.items);

        const value = try Value.List.initOwned(gc.allocator(), items);
        try gc.track(value);
        return value;
    }

    if (left.asString()) |lhs| {
        const rhs = right.asString() orelse return error.TypeError;

        const bytes = try gc.allocator().alloc(u8, lhs.len + rhs.len);
        errdefer gc.allocator().free(bytes);

        @memcpy(bytes[0..lhs.len], lhs);
        @memcpy(bytes[lhs.len..], rhs);

        const value = try Value.String.initOwned(gc.allocator(), bytes);
        try gc.track(value);
        return value;
    }

    if (left.asMap()) |lhs| {
        const rhs = right.asMap() orelse return error.TypeError;

        var entries: std.ArrayList(Value.Map.Entry) = .empty;
        errdefer entries.deinit(gc.allocator());

        for (lhs.entries) |entry| {
            try entries.append(gc.allocator(), entry);
        }
        for (rhs.entries) |entry| {
            try putMapEntryInList(&entries, gc.allocator(), entry.key, entry.value);
        }

        const owned = try entries.toOwnedSlice(gc.allocator());
        errdefer gc.allocator().free(owned);
        const value = try Value.Map.initOwned(gc.allocator(), owned);
        try gc.track(value);
        return value;
    }

    return error.TypeError;
}

fn putMapEntryInList(
    entries: *std.ArrayList(Value.Map.Entry),
    gpa: Allocator,
    key: Value,
    value: Value,
) !void {
    for (entries.items) |*entry| {
        if (entry.key.equal(key)) {
            entry.value = value;
            return;
        }
    }
    try entries.append(gpa, .{ .key = key, .value = value });
}

fn consValue(head: Value, tail: Value, gc: *Gc) anyerror!Value {
    const list = tail.asList() orelse return error.TypeError;

    const items = try gc.allocator().alloc(Value, list.items.len + 1);
    errdefer gc.allocator().free(items);

    items[0] = head;
    @memcpy(items[1..], list.items);

    const value = try Value.List.initOwned(gc.allocator(), items);
    try gc.track(value);
    return value;
}

fn literalMatches(lit: Pattern.LiteralPattern, value: Value, gpa: Allocator) anyerror!bool {
    const token = lit.token;
    return switch (token.tag) {
        .unit => switch (value) {
            .unit => true,
            else => false,
        },
        .true => switch (value) {
            .boolean => |b| b,
            else => false,
        },
        .false => switch (value) {
            .boolean => |b| !b,
            else => false,
        },
        .integer => blk: {
            const v = value.asInteger() orelse break :blk false;
            const parsed = try parseInteger(token.lexeme);
            const target = if (lit.negate) std.math.negate(parsed) catch return error.IntegerOverflow else parsed;
            break :blk v == target;
        },
        .string => blk: {
            const decoded = try decodeStringLiteral(gpa, token.lexeme);
            defer gpa.free(decoded);
            const bytes = value.asString() orelse break :blk false;
            break :blk std.mem.eql(u8, decoded, bytes);
        },
        else => false,
    };
}

fn decodeStringLiteral(gpa: Allocator, lexeme: []const u8) anyerror![]u8 {
    if (lexeme.len == 0 or (lexeme[0] != '"' and lexeme[0] != '\'')) {
        return try gpa.dupe(u8, lexeme);
    }

    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(gpa);

    var index: usize = 1;
    while (index + 1 < lexeme.len) {
        const byte = lexeme[index];
        if (byte == '\\') {
            index += 1;
            if (index + 1 > lexeme.len) return error.InvalidStringLiteral;
            const escaped = lexeme[index];
            try buffer.append(gpa, switch (escaped) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                else => return error.InvalidStringLiteral,
            });
        } else {
            try buffer.append(gpa, byte);
        }
        index += 1;
    }

    return buffer.toOwnedSlice(gpa);
}

const testing = std.testing;

fn expectEvaluatesTo(input: []const u8, expected: Value) !void {
    var gc = try Gc.init(testing.allocator, testing.io);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    try gc.track(env);
    try @import("builtins.zig").install(&gc, env);

    const owned_input = try testing.allocator.dupe(u8, input);
    defer testing.allocator.free(owned_input);
    var parser = try @import("Parser.zig").init(testing.allocator, owned_input);
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);

    const value = try evaluate(ast, &gc, env);
    try testing.expect(value.equal(expected));
}

fn expectEvalError(input: []const u8, expected: anyerror) !void {
    var gc = try Gc.init(testing.allocator, testing.io);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    try gc.track(env);
    try @import("builtins.zig").install(&gc, env);

    const owned_input = try testing.allocator.dupe(u8, input);
    defer testing.allocator.free(owned_input);
    var parser = try @import("Parser.zig").init(testing.allocator, owned_input);
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);

    try testing.expectError(expected, evaluate(ast, &gc, env));
}

test "arithmetic" {
    try expectEvaluatesTo("1 + 2 * 3", .{ .integer = 7 });
}

test "integer division truncated toward zero" {
    try expectEvaluatesTo("7 / 3", .{ .integer = 2 });
    try expectEvaluatesTo("-7 / 3", .{ .integer = -2 });
    try expectEvaluatesTo("7 % 3", .{ .integer = 1 });
    try expectEvaluatesTo("-7 % 3", .{ .integer = -1 });
}

test "unit literal evaluation" {
    try expectEvaluatesTo("()", .{ .unit = {} });
}

test "boolean operators evaluate both operands" {
    try expectEvalError("false && x", error.UnboundName);
    try expectEvalError("true || x", error.UnboundName);
    try expectEvaluatesTo("true && false", .{ .boolean = false });
    try expectEvaluatesTo("false || true", .{ .boolean = true });
}

test "binding and identifier" {
    try expectEvaluatesTo("let x = 42; x", .{ .integer = 42 });
}

test "recursive binding" {
    try expectEvaluatesTo(
        \\let fact = \ 0 -> 1 | n -> n * fact(n - 1);
        \\fact(5)
    , .{ .integer = 120 });
}

test "lambda tuple application" {
    try expectEvaluatesTo(
        \\let add = \ x, y -> x + y;
        \\add(1, 2)
    , .{ .integer = 3 });
}

test "zero-arg call passes unit" {
    try expectEvaluatesTo(
        \\let always = \ () -> 42;
        \\always()
    , .{ .integer = 42 });
}

test "match expression" {
    try expectEvaluatesTo(
        \\match [1, 2, 3] \ [] -> 0 | [x, ..] -> x
    , .{ .integer = 1 });
}

test "string indexing returns byte" {
    try expectEvaluatesTo("\"cat\"[0]", .{ .integer = 99 });
}

test "list cons" {
    var gc = try Gc.init(testing.allocator, testing.io);
    defer gc.deinit();
    const env = try Environment.init(testing.allocator, null);
    try gc.track(env);

    var parser = try @import("Parser.zig").init(testing.allocator, "1 :: [2, 3]");
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);

    const value = try evaluate(ast, &gc, env);
    const list = value.asList() orelse return error.TestExpectedList;
    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expect(list.items[0].equal(.{ .integer = 1 }));
}

test "apply non function" {
    try expectEvalError("1(2)", error.ApplyNonFunction);
}

test "no match" {
    try expectEvalError(
        \\let f = \ 0 -> 1;
        \\f(2)
    , error.NoMatch);
}

test "divide by zero" {
    try expectEvalError("1 / 0", error.DivideByZero);
}

test "index out of bounds" {
    try expectEvalError("[1, 2][5]", error.IndexOutOfBounds);
}

test "refinement pattern" {
    try expectEvaluatesTo(
        \\let classify = \ n & n > 0 -> 1 | n & n < 0 -> -1 | _ -> 0;
        \\classify(5)
    , .{ .integer = 1 });
}

test "alternative pattern" {
    try expectEvaluatesTo(
        \\let isZeroOrOne = \ 0 | 1 -> true | _ -> false;
        \\isZeroOrOne(1)
    , .{ .boolean = true });
}

test "tuple equality" {
    try expectEvaluatesTo("(1, 2) == (1, 2)", .{ .boolean = true });
}

test "tuple list inequality" {
    try expectEvaluatesTo("(1, 2) != [1, 2]", .{ .boolean = true });
}

test "unit list inequality" {
    try expectEvaluatesTo("() != []", .{ .boolean = true });
}

test "destructuring binding" {
    try expectEvaluatesTo("let x, y = (10, 20); x + y", .{ .integer = 30 });
}

test "concatenation" {
    var gc = try Gc.init(testing.allocator, testing.io);
    defer gc.deinit();
    const env = try Environment.init(testing.allocator, null);
    try gc.track(env);
    var parser = try @import("Parser.zig").init(testing.allocator,
        \\"hello" ++ " " ++ "world"
    );
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);
    const value = try evaluate(ast, &gc, env);
    const bytes = value.asString() orelse return error.TestExpectedString;
    try testing.expectEqualStrings("hello world", bytes);
}

test "sum via recursion" {
    try expectEvaluatesTo(
        \\let sum = \ [] -> 0 | [x, ..xs] -> x + sum(xs);
        \\sum([1, 2, 3, 4])
    , .{ .integer = 10 });
}

test "record literal indexing and duplicate keys" {
    try expectEvaluatesTo("{\"a\": 1, b: 2}.b", .{ .integer = 2 });
    try expectEvaluatesTo("{a: 1, \"a\": 2}.a", .{ .integer = 2 });
    try expectEvalError("{a: 1}[1]", error.TypeError);
}

test "record equality ignores entry order" {
    try expectEvaluatesTo("{a: 1, b: 2} == {b: 2, a: 1}", .{ .boolean = true });
}

test "record missing key reports runtime error" {
    try expectEvalError("{a: 1}.b", error.KeyNotFound);
}

test "member access desugars to string-key record lookup" {
    try expectEvaluatesTo("{name: 42}.name", .{ .integer = 42 });
    try expectEvaluatesTo("{user: {name: 7}}.user.name", .{ .integer = 7 });
    try expectEvaluatesTo("let id = \\ x -> x; id({name: 5}).name", .{ .integer = 5 });
    try expectEvalError("{name: 1}.missing", error.KeyNotFound);
    try expectEvalError("[1, 2].name", error.TypeError);
}

test "record concat merges right-biased" {
    try expectEvaluatesTo(
        \\let r = {a: 1} ++ {a: 2, b: 3};
        \\r.a == 2 && r.b == 3
    , .{ .boolean = true });
}

test "record builtins" {
    try expectEvaluatesTo("record.has({a: 1}, \"a\")", .{ .boolean = true });
    try expectEvaluatesTo("record.put({}, \"a\", 5).a", .{ .integer = 5 });
    try expectEvaluatesTo("record.remove({a: 1}, \"a\") == {}", .{ .boolean = true });
    try expectEvaluatesTo("record.entries({a: 1}) == [(\"a\", 1)]", .{ .boolean = true });
    try expectEvalError("record.has({}, 1)", error.TypeError);
    try expectEvalError("record.put({}, 1, 5)", error.TypeError);
    try expectEvalError("record_has({}, \"a\")", error.UnboundName);
    try expectEvalError("record.get({a: 1}, \"a\")", error.KeyNotFound);
}

test "list and tuple builtins" {
    try expectEvaluatesTo("list.size([1, 2, 3])", .{ .integer = 3 });
    try expectEvaluatesTo("list.entries([\"a\", \"b\"]) == [(0, \"a\"), (1, \"b\")]", .{ .boolean = true });
    try expectEvaluatesTo("tuple.size((true, 42, \"x\"))", .{ .integer = 3 });
    try expectEvaluatesTo("tuple.entries((\"a\", \"b\")) == [(0, \"a\"), (1, \"b\")]", .{ .boolean = true });
    try expectEvalError("list.size((1, 2))", error.TypeError);
    try expectEvalError("tuple.size([1, 2])", error.TypeError);
}

test "string builtins" {
    try expectEvaluatesTo("string.size(\"cat\")", .{ .integer = 3 });
    try expectEvaluatesTo("string.size(\"å\")", .{ .integer = 2 });
    try expectEvalError("string.size([1, 2])", error.TypeError);
}

test "pretty builtins" {
    const expected = try Value.String.init(testing.allocator, "{\n" ++
        "    status: 200,\n" ++
        "    body: {\n" ++
        "        ok: true\n" ++
        "    },\n" ++
        "    \"bad-key\": [1, 2]\n" ++
        "}");
    defer expected.deinit(testing.allocator);

    try expectEvaluatesTo(
        \\pretty.show({status: 200, body: {ok: true}, "bad-key": [1, 2]})
    , expected);
    try expectEvaluatesTo("record.has(pretty, \"print\")", .{ .boolean = true });
}

test "record patterns" {
    try expectEvaluatesTo(
        \\let f = \ {name: n} -> n | _ -> 0;
        \\f({name: 7})
    , .{ .integer = 7 });
    try expectEvaluatesTo(
        \\let f = \ {name: n} -> n | _ -> 0;
        \\f({name: 7, extra: true})
    , .{ .integer = 0 });
    try expectEvaluatesTo(
        \\let f = \ {name: n, ..} -> n | _ -> 0;
        \\f({name: 7, extra: true})
    , .{ .integer = 7 });
    try expectEvaluatesTo(
        \\let f = \ {name: n, ..rest} -> rest.extra;
        \\f({name: 7, extra: 9})
    , .{ .integer = 9 });
    try expectEvaluatesTo(
        \\let f = \ {point: (x, y), ..} -> x + y;
        \\f({point: (2, 3), extra: true})
    , .{ .integer = 5 });
    try expectEvaluatesTo(
        \\let f = \ {name: n, ..} -> n | _ -> 0;
        \\f({other: 7})
    , .{ .integer = 0 });
}

test "failed record alternatives roll back partial bindings" {
    try expectEvalError(
        \\let f = \ {a: x, b: 0} | _ -> x;
        \\f({a: 1, b: 2})
    , error.UnboundName);
}

test "failed refinement alternatives roll back pattern bindings" {
    try expectEvalError(
        \\let f = \ (x & false) | _ -> x;
        \\f(1)
    , error.UnboundName);
}

test "failed tuple alternatives roll back partial bindings" {
    try expectEvalError(
        \\let f = \ (x, 0) | (_, 1) -> x;
        \\f((42, 1))
    , error.UnboundName);
}

test "integer overflow reports runtime error" {
    try expectEvalError("9223372036854775808", error.IntegerOverflow);
    try expectEvalError("9223372036854775807 + 1", error.IntegerOverflow);
    try expectEvalError("-9223372036854775808 - 1", error.IntegerOverflow);
    try expectEvalError("-9223372036854775808 / -1", error.IntegerOverflow);
}

test "invalid string escape reports runtime error" {
    try expectEvalError("\"\\q\"", error.InvalidStringLiteral);
}
