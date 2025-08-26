const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;
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
                .symbol => try env.lookup(primary.operand.lexeme),
                else => unreachable,
            };
        },
        .abstraction => |abstraction| {
            const closure = try Value.Closure.init(self.allocator, abstraction, env);
            try self.objects.append(Object{ .value = closure });
            return closure;
        },
        .application => |application| {
            var abstraction = try self._evaluate(application.abstraction, env);
            const argument = try self._evaluate(application.argument, env);

            return switch (abstraction) {
                .closure => |closure| {
                    var scope_owned: bool = false;
                    var scope = try Environment.init(self.allocator, closure.env);
                    errdefer if (!scope_owned) scope.deinitSelf(self.allocator);

                    try scope.define(self.allocator, closure.parameter, argument);
                    try self.objects.append(Object{ .env = scope });
                    scope_owned = true;

                    const body = try closure.body.clone(self.allocator);
                    try self.objects.append(Object{ .node = body });
                    return try self._evaluate(body, scope);
                },
                .builtin => |builtin| {
                    const result = try builtin.function(argument, env, builtin.capture_env);
                    defer abstraction.deinit(self.allocator);
                    return result;
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
            var scope_owned: bool = false;
            var scope = try Environment.init(self.allocator, env);
            errdefer if (!scope_owned) scope.deinitSelf(self.allocator);

            const name = let_in.name.lexeme;
            try scope.define(self.allocator, name, Value.Free.init());

            const value = try self._evaluate(let_in.value, scope);
            if (value.isFree()) return error.RecursiveBinding;
            try scope.bind(name, value);

            try self.objects.append(Object{ .env = scope });
            scope_owned = true;

            return try self._evaluate(let_in.body, scope);
        },
        .let_rec_in => |let_rec_in| {
            var scope_owned: bool = false;
            var scope = try Environment.init(self.allocator, env);
            errdefer if (!scope_owned) scope.deinitSelf(self.allocator);

            const name = let_rec_in.name.lexeme;
            try scope.define(self.allocator, name, Value.Free.init());
            const value = try self._evaluate(let_rec_in.value, scope);

            if (value.asFunction() == null) return error.RecursiveBinding;

            try scope.bind(name, value);

            try self.objects.append(Object{ .env = scope });
            scope_owned = true;

            return try self._evaluate(let_rec_in.body, scope);
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

test "let-in recursive" {
    // let x = x in x
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, "x"),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    try expectError(error.RecursiveBinding, interpreter.evaluate(ast));
}

test "let-in recursive nested" {
    // let one = 1 in let two = two in one two
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
            try Node.LetIn.init(
                testing.allocator,
                Token.init(.symbol, "two"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, "two")),
                try Node.Application.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, "one")),
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, "two")),
                ),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    try expectError(error.RecursiveBinding, interpreter.evaluate(ast));
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

test "let-rec closure allowed" {
    // let rec f = (\x. x) in f
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, "f"),
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "f")),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    const actual = try interpreter.evaluate(ast);
    try expect(actual.asFunction() != null);
}

test "let-rec non-function" {
    // let rec x = 1 in x
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, "x"),
            try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, "x")),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    try expectError(error.RecursiveBinding, interpreter.evaluate(ast));
}

test "let-rec nested" {
    // let rec one = (\z. 1) in
    //   let rec two = (\w. one w) in
    //     one two
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, "one"),
            try Node.Abstraction.init(
                testing.allocator,
                Token.init(.symbol, "z"),
                try Node.Primary.init(testing.allocator, Token.init(.number, "1")),
            ),
            try Node.LetRecIn.init(
                testing.allocator,
                Token.init(.symbol, "two"),
                try Node.Abstraction.init(
                    testing.allocator,
                    Token.init(.symbol, "w"),
                    try Node.Application.init(
                        testing.allocator,
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, "one")),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, "w")),
                    ),
                ),
                try Node.Application.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, "one")),
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, "two")),
                ),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(1);
    try runTest(testing.allocator, ast, expected);
}
