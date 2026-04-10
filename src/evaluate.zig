const std = @import("std");
const Allocator = std.mem.Allocator;
const parseFloat = std.fmt.parseFloat;

const Environment = @import("Environment.zig");
const Gc = @import("Gc.zig");
const Node = @import("node.zig");
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;

pub fn evaluate(node: *Node.Node, gc: *Gc, env: *Environment) anyerror!Value {
    return evalNode(node, gc, env);
}

fn evalNode(node: *Node.Node, gc: *Gc, env: *Environment) anyerror!Value {
    return switch (node.*) {
        .program => |program| evalNode(program.expression, gc, env),
        .identifier => |token| env.get(token.lexeme),
        .literal => |token| evalLiteral(token, gc),
        .unary => |unary| evalUnary(unary, gc, env),
        .binary => |binary| evalBinary(binary, gc, env),
        .call => |call| evalCall(call, gc, env),
        .list => |list| evalList(list, gc, env),
        .range => |range| evalRange(range, gc, env),
        .block => |block| evalBlock(block, gc, env),
        .function => |function| evalFunction(function, gc, env),
        .binding => |binding| evalBinding(binding, gc, env),
        .sequence => |sequence| blk: {
            _ = try evalNode(sequence.first, gc, env);
            break :blk try evalNode(sequence.second, gc, env);
        },
    };
}

fn evalLiteral(token: Token, gc: *Gc) anyerror!Value {
    return switch (token.tag) {
        .true => .{ .boolean = true },
        .false => .{ .boolean = false },
        .number => .{ .number = try parseFloat(f64, token.lexeme) },
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

fn evalUnary(unary: Node.Node.Unary, gc: *Gc, env: *Environment) anyerror!Value {
    const operand = try evalNode(unary.operand, gc, env);
    return switch (unary.operator.tag) {
        .minus => .{ .number = -(operand.asNumber() orelse return error.TypeError) },
        .not => .{ .boolean = !(operand.asBoolean() orelse return error.TypeError) },
        else => unreachable,
    };
}

fn evalBinary(binary: Node.Node.Binary, gc: *Gc, env: *Environment) anyerror!Value {
    const left = try evalNode(binary.left, gc, env);
    const right = try evalNode(binary.right, gc, env);

    return switch (binary.operator.tag) {
        .equal => .{ .boolean = left.equal(right) },
        .not_equal => .{ .boolean = !left.equal(right) },
        .greater => compareNumbers(left, right, .greater),
        .greater_equal => compareNumbers(left, right, .greater_equal),
        .less => compareNumbers(left, right, .less),
        .less_equal => compareNumbers(left, right, .less_equal),
        .plus => arithmetic(left, right, .plus),
        .minus => arithmetic(left, right, .minus),
        .star => arithmetic(left, right, .star),
        .slash => arithmetic(left, right, .slash),
        .percent => arithmetic(left, right, .percent),
        .concat => concatValues(left, right, gc),
        else => unreachable,
    };
}

fn evalCall(call: Node.Node.Call, gc: *Gc, env: *Environment) anyerror!Value {
    const callee = try evalNode(call.callee, gc, env);

    var arguments = std.ArrayList(Value).empty;
    defer arguments.deinit(gc.allocator());

    for (call.arguments) |argument| {
        try arguments.append(gc.allocator(), try evalNode(argument, gc, env));
    }

    if (callee.asNative()) |native| {
        return native.function(arguments.items);
    }

    const closure = callee.asClosure() orelse return error.NotCallable;
    if (closure.parameters.len != arguments.items.len) return error.ArityMismatch;

    return switch (closure.body) {
        .expression => |body_expression| blk: {
            const scope = try bindParameters(gc, closure.env, closure.parameters, arguments.items);
            try gc.track(scope);
            break :blk try evalNode(body_expression, gc, scope);
        },
        .branches => |branches| evalBranches(branches, closure, arguments.items, gc),
    };
}

fn evalList(list: Node.Node.List, gc: *Gc, env: *Environment) anyerror!Value {
    var items = std.ArrayList(Value).empty;
    errdefer items.deinit(gc.allocator());

    for (list.items) |item| {
        try items.append(gc.allocator(), try evalNode(item, gc, env));
    }

    if (list.spread) |spread| {
        const spread_value = try evalNode(spread, gc, env);
        const spread_list = spread_value.asList() orelse return error.TypeError;
        try items.appendSlice(gc.allocator(), spread_list.items);
    }

    const owned_items = try items.toOwnedSlice(gc.allocator());
    errdefer gc.allocator().free(owned_items);
    const value = try Value.List.initOwned(gc.allocator(), owned_items);
    try gc.track(value);
    return value;
}

fn evalRange(range: Node.Node.Range, gc: *Gc, env: *Environment) anyerror!Value {
    const start_value = try evalNode(range.start, gc, env);
    const end_value = try evalNode(range.end, gc, env);

    const start_number = start_value.asNumber() orelse return error.TypeError;
    const end_number = end_value.asNumber() orelse return error.TypeError;
    if (@floor(start_number) != start_number or @floor(end_number) != end_number) {
        return error.InvalidRange;
    }

    const start_int: i64 = @intFromFloat(start_number);
    const end_int: i64 = @intFromFloat(end_number);
    const len: usize = @intCast(@abs(end_int - start_int) + 1);
    const step: i64 = if (start_int <= end_int) 1 else -1;

    const items = try gc.allocator().alloc(Value, len);
    errdefer gc.allocator().free(items);

    var current = start_int;
    for (items) |*slot| {
        slot.* = .{ .number = @floatFromInt(current) };
        current += step;
    }

    const value = try Value.List.initOwned(gc.allocator(), items);
    try gc.track(value);
    return value;
}

fn evalBlock(block: Node.Node.Block, gc: *Gc, env: *Environment) anyerror!Value {
    const scope = try Environment.init(gc.allocator(), env);
    var keep = false;
    errdefer if (!keep) scope.deinit();
    try gc.track(scope);
    keep = true;
    return evalNode(block.expression, gc, scope);
}

fn evalFunction(function: Node.Node.Function, gc: *Gc, env: *Environment) anyerror!Value {
    const value = try Value.Closure.init(gc.allocator(), function.parameters, function.body, env);
    try gc.track(value);
    return value;
}

fn evalBinding(binding: Node.Node.Binding, gc: *Gc, env: *Environment) anyerror!Value {
    if (binding.pattern.* == .identifier and binding.value.* == .function) {
        const name = binding.pattern.identifier.lexeme;
        const scope = try Environment.init(gc.allocator(), env);
        var keep = false;
        errdefer if (!keep) scope.deinit();

        try scope.bind(name, null);
        const value = try evalNode(binding.value, gc, scope);
        try scope.set(name, value);
        try gc.track(scope);
        keep = true;
        return evalNode(binding.body, gc, scope);
    }

    const value = try evalNode(binding.value, gc, env);
    const scope = try Environment.init(gc.allocator(), env);
    var keep = false;
    errdefer if (!keep) scope.deinit();

    if (!try matchPattern(binding.pattern, value, scope, gc)) {
        return error.PatternMatchFailure;
    }

    try gc.track(scope);
    keep = true;
    return evalNode(binding.body, gc, scope);
}

fn evalBranches(
    branches: []*Node.Branch,
    closure: *Value.Closure,
    arguments: []const Value,
    gc: *Gc,
) anyerror!Value {
    for (branches) |branch| {
        if (try prepareBranchScope(branch, closure, arguments, gc)) |scope| {
            return evalNode(branch.result, gc, scope);
        }
    }
    return error.NoMatchingBranch;
}

fn prepareBranchScope(
    branch: *Node.Branch,
    closure: *Value.Closure,
    arguments: []const Value,
    gc: *Gc,
) anyerror!?*Environment {
    const scope = try Environment.init(gc.allocator(), closure.env);
    var keep = false;
    defer if (!keep) scope.deinit();

    if (branch.patterns) |patterns| {
        if (patterns.len != arguments.len) return null;
        for (patterns, arguments) |pattern, argument| {
            if (!try matchPattern(pattern, argument, scope, gc)) return null;
        }
    } else {
        if (closure.parameters.len != arguments.len) return error.ArityMismatch;
        for (closure.parameters, arguments) |parameter, argument| {
            try scope.bind(parameter.lexeme, argument);
        }
    }

    if (branch.guard) |guard| {
        const guard_value = try evalNode(guard, gc, scope);
        const guard_bool = guard_value.asBoolean() orelse return error.NotBoolean;
        if (!guard_bool) return null;
    }

    try gc.track(scope);
    keep = true;
    return scope;
}

fn bindParameters(
    gc: *Gc,
    parent: *Environment,
    parameters: []const Token,
    arguments: []const Value,
) anyerror!*Environment {
    const scope = try Environment.init(gc.allocator(), parent);
    errdefer scope.deinit();

    for (parameters, arguments) |parameter, argument| {
        try scope.bind(parameter.lexeme, argument);
    }

    return scope;
}

fn matchPattern(pattern: *Node.Pattern, value: Value, env: *Environment, gc: *Gc) anyerror!bool {
    return switch (pattern.*) {
        .wildcard => true,
        .identifier => |token| blk: {
            env.bind(token.lexeme, value) catch |err| switch (err) {
                error.AlreadyDefined => return error.DuplicatePatternBinding,
                else => return err,
            };
            break :blk true;
        },
        .literal => |token| try literalMatches(token, value, gc.allocator()),
        .group => |inner| matchPattern(inner, value, env, gc),
        .list => |list_pattern| matchListPattern(list_pattern, value, env, gc),
    };
}

fn matchListPattern(
    pattern: Node.Pattern.ListPattern,
    value: Value,
    env: *Environment,
    gc: *Gc,
) anyerror!bool {
    const list = value.asList() orelse return false;
    if (pattern.spread == null and list.items.len != pattern.items.len) return false;
    if (pattern.spread != null and list.items.len < pattern.items.len) return false;

    for (pattern.items, 0..) |item_pattern, index| {
        if (!try matchPattern(item_pattern, list.items[index], env, gc)) return false;
    }

    if (pattern.spread) |spread| {
        const suffix = list.items[pattern.items.len..];
        const tail = try Value.List.init(gc.allocator(), suffix);
        try gc.track(tail);
        return matchPattern(spread, tail, env, gc);
    }

    return true;
}

const Comparison = enum { greater, greater_equal, less, less_equal };

fn compareNumbers(left: Value, right: Value, comparison: Comparison) anyerror!Value {
    const lhs = left.asNumber() orelse return error.TypeError;
    const rhs = right.asNumber() orelse return error.TypeError;
    return .{
        .boolean = switch (comparison) {
            .greater => lhs > rhs,
            .greater_equal => lhs >= rhs,
            .less => lhs < rhs,
            .less_equal => lhs <= rhs,
        },
    };
}

const Arithmetic = enum { plus, minus, star, slash, percent };

fn arithmetic(left: Value, right: Value, operation: Arithmetic) anyerror!Value {
    const lhs = left.asNumber() orelse return error.TypeError;
    const rhs = right.asNumber() orelse return error.TypeError;

    return switch (operation) {
        .plus => .{ .number = lhs + rhs },
        .minus => .{ .number = lhs - rhs },
        .star => .{ .number = lhs * rhs },
        .slash => blk: {
            if (rhs == 0) return error.DivisionByZero;
            break :blk .{ .number = lhs / rhs };
        },
        .percent => blk: {
            if (rhs == 0) return error.DivisionByZero;
            break :blk .{ .number = lhs - @floor(lhs / rhs) * rhs };
        },
    };
}

fn concatValues(left: Value, right: Value, gc: *Gc) anyerror!Value {
    if (left.asList()) |lhs| {
        const rhs = right.asList() orelse return error.TypeError;

        var items = try gc.allocator().alloc(Value, lhs.items.len + rhs.items.len);
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

    return error.TypeError;
}

fn literalMatches(token: Token, value: Value, gpa: Allocator) anyerror!bool {
    return switch (token.tag) {
        .true => switch (value) {
            .boolean => |boolean| boolean,
            else => false,
        },
        .false => switch (value) {
            .boolean => |boolean| !boolean,
            else => false,
        },
        .number => (value.asNumber()) != null and (value.asNumber().? == try parseFloat(f64, token.lexeme)),
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
    var buffer = std.ArrayList(u8).empty;
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
                else => escaped,
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
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    defer env.deinit();
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

fn expectEvaluationError(input: []const u8, expected: anyerror) !void {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try @import("builtins.zig").install(&gc, env);

    const owned_input = try testing.allocator.dupe(u8, input);
    defer testing.allocator.free(owned_input);
    var parser = try @import("Parser.zig").init(testing.allocator, owned_input);
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);

    try testing.expectError(expected, evaluate(ast, &gc, env));
}

test "evaluates arithmetic" {
    try expectEvaluatesTo("1 + 2 * 3", .{ .number = 7 });
}

test "evaluates unary boolean negation" {
    try expectEvaluatesTo("!false", .{ .boolean = true });
}

test "evaluates string concatenation" {
    const expected = try Value.String.init(testing.allocator, "ab");
    defer expected.deinit(testing.allocator);
    try expectEvaluatesTo("\"a\" ++ \"b\"", expected);
}

test "concat rejects mixed types" {
    try expectEvaluationError("\"a\" ++ [1]", error.TypeError);
}

test "evaluates simple function application" {
    try expectEvaluatesTo(
        \\let add = (x, y) { x + y };
        \\add(1, 2)
    , .{ .number = 3 });
}

test "evaluates branch selection" {
    try expectEvaluatesTo(
        \\let abs = (n) {
        \\    ? n >= 0 => n,
        \\    => -n
        \\};
        \\abs(-5)
    , .{ .number = 5 });
}

test "evaluates recursive functions" {
    try expectEvaluatesTo(
        \\let sum = (xs) {
        \\    [] => 0,
        \\    [head, ...tail] => head + sum(tail)
        \\};
        \\sum([1..5])
    , .{ .number = 15 });
}

test "evaluates pattern binding" {
    try expectEvaluatesTo(
        \\let [head, ..._] = [1, 2, 3];
        \\head
    , .{ .number = 1 });
}

test "evaluates list spread and range" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try @import("builtins.zig").install(&gc, env);

    const input =
        \\let xs = [1..3];
        \\[0, ...xs]
    ;
    var parser = try @import("Parser.zig").init(testing.allocator, input);
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);
    const value = try evaluate(ast, &gc, env);

    const list = value.asList() orelse return error.TestExpectedList;
    try testing.expectEqual(@as(usize, 4), list.items.len);
    try testing.expect(list.items[0].equal(.{ .number = 0 }));
    try testing.expect(list.items[3].equal(.{ .number = 3 }));
}

test "binding pattern failure errors" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try @import("builtins.zig").install(&gc, env);
    var parser = try @import("Parser.zig").init(testing.allocator,
        \\let [] = [1];
        \\0
    );
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);
    try testing.expectError(error.PatternMatchFailure, evaluate(ast, &gc, env));
}

test "branch failure errors" {
    var gc = try Gc.init(testing.allocator);
    defer gc.deinit();

    const env = try Environment.init(testing.allocator, null);
    defer env.deinit();
    try @import("builtins.zig").install(&gc, env);
    var parser = try @import("Parser.zig").init(testing.allocator,
        \\let f = (x) {
        \\    0 => 1
        \\};
        \\f(2)
    );
    defer parser.deinit();
    const ast = try parser.parse();
    defer ast.deinit(testing.allocator);
    try testing.expectError(error.NoMatchingBranch, evaluate(ast, &gc, env));
}
