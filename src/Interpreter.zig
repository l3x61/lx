const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const expect = testing.expect;
const print = std.debug.print;

const ansi = @import("ansi.zig");
const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Object = @import("object.zig").Object;
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;

const Interpreter = @This();

allocator: Allocator,
env: *Environment,
objects: ArrayList(Object),

pub fn init(allocator: Allocator, env: ?*Environment) !Interpreter {
    return Interpreter{
        .allocator = allocator,
        .objects = ArrayList(Object).init(allocator),
        .env = try Environment.init(allocator, env),
    };
}

pub fn deinit(self: *Interpreter) void {
    for (self.objects.items) |*object| {
        object.deinit(self.allocator);
    }
    self.objects.deinit();
    self.env.deinitAll(self.allocator);
}

pub fn evaluate(self: *Interpreter, node: *Node) !Value {
    return self._evaluate(node, self.env);
}

pub fn _evaluate(self: *Interpreter, node: *Node, env: *Environment) !Value {
    return switch (node.*) {
        .program => |program| {
            const expression = program.expression orelse
                return Value.Null.init();
            return try self._evaluate(expression, env);
        },
        .primary => |primary| {
            const operand = primary.operand;
            return switch (operand.tag) {
                .null => Value.Null.init(),
                .true => Value.Boolean.init(true),
                .false => Value.Boolean.init(false),
                .number => try Value.Number.parse(operand.lexeme),
                .symbol => env.lookup(primary.operand.lexeme) orelse Value.Null.init(),
                else => unreachable,
            };
        },
        .abstraction => |abstraction| {
            const closure = try Value.Closure.init(self.allocator, abstraction, env);
            try self.objects.append(Object{ .value = closure });
            return closure;
        },
        .application => |application| {
            const abstraction = try self._evaluate(application.abstraction, env);
            const argument = try self._evaluate(application.argument, env);

            return switch (abstraction) {
                .closure => |closure| {
                    var child_env = try Environment.init(self.allocator, closure.env);
                    try child_env.define(self.allocator, closure.parameter, argument);
                    try self.objects.append(Object{ .env = child_env });

                    const body = try closure.body.clone(self.allocator);
                    try self.objects.append(Object{ .node = body });
                    return try self._evaluate(body, child_env);
                },
                .builtin => |builtin| {
                    return try builtin.function(argument, env);
                },
                else => {
                    print("can not apply {s}{s}{s} to {s}{s}{s}\n", .{
                        ansi.dimmed,
                        application.abstraction,
                        ansi.reset,
                        ansi.dimmed,
                        application.argument,
                        ansi.reset,
                    });
                    return error.NotCallable;
                },
            };
        },
        .let => |let| {
            const name = let.name.lexeme;
            const value = try self._evaluate(let.value, env);
            try env.define(self.allocator, name, value);

            return value;
        },
        .let_in => |let_in| {
            var scope = try Environment.init(self.allocator, env);
            const name = let_in.name.lexeme;
            const value = try self._evaluate(let_in.value, scope);
            try scope.define(self.allocator, name, value);
            try self.objects.append(Object{ .env = scope });

            return try self._evaluate(let_in.body, scope);
        },
        .if_then_else => |if_then_else| {
            const condition = try self._evaluate(if_then_else.condition, env);
            if (condition.asBoolean()) |boolean| {
                return if (boolean)
                    self._evaluate(if_then_else.consequent, env)
                else
                    self._evaluate(if_then_else.alternate, env);
            } else {
                return error.NotABoolean;
            }
        },
    };
}

fn runTest(allocator: Allocator, node: *Node, expected: Value) !void {
    var interpreter = try Interpreter.init(allocator, null);
    defer interpreter.deinit();

    const actual = try interpreter.evaluate(node);

    expect(expected.equal(actual)) catch |err| {
        print("expected {s} but got {s}\n", .{ expected, actual });
        return err;
    };
}

test "empty" {
    const ast = try Node.Program.init(testing.allocator, null);
    defer ast.deinit(testing.allocator);

    const expected = Value.Null.init();
    try runTest(testing.allocator, ast, expected);
}

test "number" {
    // 123
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Primary.init(testing.allocator, Token.init(.number, "123")),
    );
    defer ast.deinit(testing.allocator);
    const expected = Value.Number.init(123);

    try runTest(testing.allocator, ast, expected);
}

test "application" {
    // (λx. x) 123
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, "123")),
        ),
    );
    defer ast.deinit(testing.allocator);
    const expected = Value.Number.init(123);

    try runTest(testing.allocator, ast, expected);
}

test "return" {
    // (λx. 999) 123
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.number, "999")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, "123")),
        ),
    );
    defer ast.deinit(testing.allocator);
    const expected = Value.Number.init(999);

    try runTest(testing.allocator, ast, expected);
}

test "shadowing" {
    // (λx. (λx. x) 2) 1
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "x"),
                try Node.Application.init(
                    testing.allocator,
                    try Node.Abstraction.init(
                        testing.allocator,
                        Token.init(.symbol, "x"),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
                    ),
                    try Node.Primary.init(testing.allocator, Token.init(.number, "2")),
                ),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(2);
    try runTest(testing.allocator, ast, expected);
}

test "closure" {
    // (λx. (λy. x)) -1 -2
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Application.init(
            testing.allocator,
            try Node.Application.init(
                testing.allocator,
                try Node.Abstraction.init(
                    testing.allocator,
                    Token.init(.symbol, "x"),
                    try Node.Abstraction.init(
                        testing.allocator,
                        Token.init(.symbol, "y"),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
                    ),
                ),
                try Node.Primary.init(testing.allocator, Token.init(.number, "-1")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, "-2")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(-1);
    try runTest(testing.allocator, ast, expected);
}

test "let-in" {
    // let one = 1 in one
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "one")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(1);
    try runTest(testing.allocator, ast, expected);
}

test "literals" {
    // if null then true else false
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.IfThenElse.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.null, "null")),
            try Node.Primary.init(testing.allocator, Token.init(.true, "true")),
            try Node.Primary.init(testing.allocator, Token.init(.false, "false")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Boolean.init(false);
    try runTest(testing.allocator, ast, expected);
}
