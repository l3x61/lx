const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListAligned;
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

const log = std.log.scoped(.eval);

const Interpreter = @This();
const Objects = std.array_list.AlignedManaged(Object, null);

ator: Allocator,
env: *Environment,
objects: Objects,

pub fn init(ator: Allocator, env: ?*Environment) !Interpreter {
    return Interpreter{
        .ator = ator,
        .objects = Objects.init(ator),
        .env = try Environment.init(ator, env),
    };
}

pub fn deinit(self: *Interpreter) void {
    for (self.objects.items) |*object| {
        object.deinit(self.ator);
    }
    self.objects.deinit();
    self.env.deinitAll(self.ator);
}

pub fn evaluate(self: *Interpreter, node: *Node) !Value {
    return self._evaluate(node, self.env);
}

fn _evaluate(self: *Interpreter, node: *Node, env: *Environment) !Value {
    return switch (node.*) {
        .program => |program| {
            const expression = program.expression orelse return Value.init();
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
        .binary => |binary| {
            const left = try self._evaluate(binary.left, env);
            const right = try self._evaluate(binary.right, env);

            switch (binary.operator.tag) {
                .equal => return Value.Boolean.init(left.equal(right)),
                .not_equal => return Value.Boolean.init(!left.equal(right)),
                else => {},
            }

            const left_number = left.asNumber();
            const right_number = right.asNumber();

            if (left_number == null or right_number == null) {
                const operation = switch (binary.operator.tag) {
                    .plus => "add",
                    .minus => "subtract",
                    .star => "multiply",
                    .slash => "divide",
                    else => unreachable,
                };
                const preposition = switch (binary.operator.tag) {
                    .plus => "to",
                    .minus => "from",
                    .star => "with",
                    .slash => "by",
                    else => unreachable,
                };
                log.err("can not {s} {f} {s} {f}\n", .{ operation, left.tag(), preposition, right.tag() });
                return error.TypeError;
            }

            const lnum = left_number.?;
            const rnum = right_number.?;

            const result = switch (binary.operator.tag) {
                .plus => lnum + rnum,
                .minus => lnum - rnum,
                .star => lnum * rnum,
                .slash => {
                    if (rnum == 0) {
                        log.err("division by 0 in expression {f}\n", .{node});
                        return error.DivisionByZero;
                    }
                    return Value.Number.init(lnum / rnum);
                },
                else => unreachable,
            };

            return Value.Number.init(result);
        },
        .function => |function| {
            const closure = try Value.Closure.init(self.ator, function, env);
            try self.objects.append(Object{ .value = closure });
            return closure;
        },
        .apply => |apply| {
            var function = try self._evaluate(apply.function, env);
            const argument = try self._evaluate(apply.argument, env);

            return switch (function) {
                .closure => |closure| {
                    var scope_owned: bool = false;
                    var scope = try Environment.init(self.ator, closure.env);
                    errdefer if (!scope_owned) scope.deinitSelf(self.ator);

                    try scope.define(self.ator, closure.parameter, argument);
                    try self.objects.append(Object{ .env = scope });
                    scope_owned = true;

                    const body = try closure.body.clone(self.ator);
                    try self.objects.append(Object{ .node = body });
                    return try self._evaluate(body, scope);
                },
                .builtin => |builtin| {
                    const result = try builtin.function(argument, env, builtin.capture_env);
                    defer function.deinit(self.ator);
                    return result;
                },
                else => {
                    log.err("can not apply {f} to {f}\n", .{ apply.function, apply.argument });
                    return error.NotCallable;
                },
            };
        },
        .let_in => |let_in| {
            var scope_owned: bool = false;
            var scope = try Environment.init(self.ator, env);
            errdefer if (!scope_owned) {
                scope.deinitSelf(self.ator);
            };

            const name = let_in.name.lexeme;
            try scope.define(self.ator, name, Value.init());

            const value = try self._evaluate(let_in.value, scope);
            if (value.isVoid()) {
                log.err("let does not allow recursive bindings\n", .{}); // TODO: report line number
                return error.RecursiveBinding;
            }
            try scope.bind(name, value);

            try self.objects.append(Object{ .env = scope });
            scope_owned = true;

            return try self._evaluate(let_in.body, scope);
        },
        .let_rec_in => |let_rec_in| {
            var scope_owned: bool = false;
            var scope = try Environment.init(self.ator, env);
            errdefer if (!scope_owned) {
                scope.deinitSelf(self.ator);
            };

            const name = let_rec_in.name.lexeme;
            try scope.define(self.ator, name, Value.init());
            const value = try self._evaluate(let_rec_in.value, scope);

            if (value.asClosure() == null) {
                log.err("let rec only allows recursive bindings for functions\n", .{}); // TODO: report line number
                return error.RecursiveBinding;
            }

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
                log.err("{f} is not a boolean\n", .{condition});
                return error.NotABoolean;
            }
        },
    };
}

fn runTest(ator: Allocator, node: *Node, expected: Value) !void {
    var interpreter = try Interpreter.init(ator, null);
    defer interpreter.deinit();

    const actual = try interpreter.evaluate(node);

    expect(expected.equal(actual)) catch |err| {
        print("expected {f} but got {f}\n", .{ expected, actual });
        return err;
    };
}

test "empty" {
    const ast = try Node.Program.init(testing.allocator, null);
    defer ast.deinit(testing.allocator);

    const expected = Value.init();
    try runTest(testing.allocator, ast, expected);
}

test "number" {
    // 123
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Primary.init(testing.allocator, Token.init(.number, input, "123")),
    );
    defer ast.deinit(testing.allocator);
    const expected = Value.Number.init(123);

    try runTest(testing.allocator, ast, expected);
}

test "apply" {
    // (λx. x) 123
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Apply.init(
            testing.allocator,
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "123")),
        ),
    );
    defer ast.deinit(testing.allocator);
    const expected = Value.Number.init(123);

    try runTest(testing.allocator, ast, expected);
}

test "return" {
    // (λx. 999) 123
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Apply.init(
            testing.allocator,
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "999")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "123")),
        ),
    );
    defer ast.deinit(testing.allocator);
    const expected = Value.Number.init(999);

    try runTest(testing.allocator, ast, expected);
}

test "shadowing" {
    // (λx. (λx. x) 2) 1
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Apply.init(
            testing.allocator,
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "x"),
                try Node.Apply.init(
                    testing.allocator,
                    try Node.Function.init(
                        testing.allocator,
                        Token.init(.symbol, input, "x"),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
                    ),
                    try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
                ),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(2);
    try runTest(testing.allocator, ast, expected);
}

test "closure" {
    // (λx. (λy. x)) -1 -2
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Apply.init(
            testing.allocator,
            try Node.Apply.init(
                testing.allocator,
                try Node.Function.init(
                    testing.allocator,
                    Token.init(.symbol, input, "x"),
                    try Node.Function.init(
                        testing.allocator,
                        Token.init(.symbol, input, "y"),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
                    ),
                ),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "-1")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "-2")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(-1);
    try runTest(testing.allocator, ast, expected);
}

test "let-in" {
    // let one = 1 in one
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, input, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "one")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(1);
    try runTest(testing.allocator, ast, expected);
}

test "let-in recursive" {
    // let x = x in x
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, input, "x"),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    try expectError(error.RecursiveBinding, interpreter.evaluate(ast));
}

test "let-in recursive nested" {
    // let one = 1 in let two = two in one two
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetIn.init(
            testing.allocator,
            Token.init(.symbol, input, "one"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            try Node.LetIn.init(
                testing.allocator,
                Token.init(.symbol, input, "two"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "two")),
                try Node.Apply.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "one")),
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "two")),
                ),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    try expectError(error.RecursiveBinding, interpreter.evaluate(ast));
}

test "evaluate equality" {
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.eqeq, input, "=="),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Boolean.init(true);
    try runTest(testing.allocator, ast, expected);
}

test "evaluate inequality" {
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.noteq, input, "!="),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Boolean.init(true);
    try runTest(testing.allocator, ast, expected);
}

test "literals" {
    // if null then true else false
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.IfThenElse.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.null, input, "null")),
            try Node.Primary.init(testing.allocator, Token.init(.true, input, "true")),
            try Node.Primary.init(testing.allocator, Token.init(.false, input, "false")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Boolean.init(false);
    try runTest(testing.allocator, ast, expected);
}

test "let-rec closure allowed" {
    // let rec f = (\x. x) in f
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, input, "f"),
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "x"),
                try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
            ),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "f")),
        ),
    );
    defer ast.deinit(testing.allocator);

    var interpreter = try Interpreter.init(testing.allocator, null);
    defer interpreter.deinit();

    const actual = try interpreter.evaluate(ast);
    try expect(actual.asClosure() != null);
}

test "let-rec non-function" {
    // let rec x = 1 in x
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, input, "x"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "x")),
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
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, input, "one"),
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "z"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            ),
            try Node.LetRecIn.init(
                testing.allocator,
                Token.init(.symbol, input, "two"),
                try Node.Function.init(
                    testing.allocator,
                    Token.init(.symbol, input, "w"),
                    try Node.Apply.init(
                        testing.allocator,
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "one")),
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "w")),
                    ),
                ),
                try Node.Apply.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "one")),
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "two")),
                ),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(1);
    try runTest(testing.allocator, ast, expected);
}

test "multiplication precedence over addition" {
    // 1 + 2 * 3 = 7
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
            Token.init(.plus, input, "+"),
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
                Token.init(.star, input, "*"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(7);
    try runTest(testing.allocator, ast, expected);
}

test "arithmetic expression" {
    // (1 + 2) * 3 = 9
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.Binary.init(
            testing.allocator,
            try Node.Binary.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                Token.init(.plus, input, "+"),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "2")),
            ),
            Token.init(.star, input, "*"),
            try Node.Primary.init(testing.allocator, Token.init(.number, input, "3")),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(9);
    try runTest(testing.allocator, ast, expected);
}

test "recursive call" {
    // fn called with true -> returns false
    // fn called with false -> returns 1234

    // (one liner)
    // let rec fn = \var. if var then fn false else 1234 in fn false

    // let rec fn = \var. if var then
    //     fn false
    // else
    //     1234
    // in
    //     fn false
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, input, "fn"),
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "var"),
                try Node.IfThenElse.init(
                    testing.allocator,
                    try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "var")),
                    try Node.Apply.init(
                        testing.allocator,
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "fn")),
                        try Node.Primary.init(testing.allocator, Token.init(.false, input, "false")),
                    ),
                    try Node.Primary.init(testing.allocator, Token.init(.number, input, "1234")),
                ),
            ),
            try Node.Apply.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "fn")),
                try Node.Primary.init(testing.allocator, Token.init(.false, input, "false")),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(1234);
    try runTest(testing.allocator, ast, expected);
}

test "factorial" {
    // let rec fact = \n. if n == 0 then 1 else n * fact (n - 1) in fact 5
    const input = "";
    const ast = try Node.Program.init(
        testing.allocator,
        try Node.LetRecIn.init(
            testing.allocator,
            Token.init(.symbol, input, "fact"),
            try Node.Function.init(
                testing.allocator,
                Token.init(.symbol, input, "n"),
                try Node.IfThenElse.init(
                    testing.allocator,
                    try Node.Binary.init(
                        testing.allocator,
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "n")),
                        Token.init(.eqeq, input, "=="),
                        try Node.Primary.init(testing.allocator, Token.init(.number, input, "0")),
                    ),
                    try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                    try Node.Binary.init(
                        testing.allocator,
                        try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "n")),
                        Token.init(.star, input, "*"),
                        try Node.Apply.init(
                            testing.allocator,
                            try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "fact")),
                            try Node.Binary.init(
                                testing.allocator,
                                try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "n")),
                                Token.init(.minus, input, "-"),
                                try Node.Primary.init(testing.allocator, Token.init(.number, input, "1")),
                            ),
                        ),
                    ),
                ),
            ),
            try Node.Apply.init(
                testing.allocator,
                try Node.Primary.init(testing.allocator, Token.init(.symbol, input, "fact")),
                try Node.Primary.init(testing.allocator, Token.init(.number, input, "5")),
            ),
        ),
    );
    defer ast.deinit(testing.allocator);

    const expected = Value.Number.init(120);
    try runTest(testing.allocator, ast, expected);
}
