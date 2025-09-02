const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Object = @import("object.zig").Object;
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;

const log = std.log.scoped(.eval);

pub fn evaluate(
    gpa: Allocator,
    node: *Node,
    env: *Environment,
    objects: *ArrayList(Object),
) !Value {
    return evaluate_(gpa, node, env, objects);
}

fn evaluate_(
    gpa: Allocator,
    node: *Node,
    env: *Environment,
    objects: *ArrayList(Object),
) !Value {
    return switch (node.*) {
        .program => |program| {
            const expression = program.expression orelse return Value.init();
            return try evaluate_(gpa, expression, env, objects);
        },
        .primary => |primary| {
            const operand = primary.operand;
            return switch (operand.tag) {
                .null => Value.Null.init(),
                .true => Value.Boolean.init(true),
                .false => Value.Boolean.init(false),
                .number => try Value.Number.parse(operand.lexeme),
                .identifier => try env.lookup(primary.operand.lexeme),
                else => unreachable,
            };
        },
        .binary => |binary| {
            const left = try evaluate_(gpa, binary.left, env, objects);
            const right = try evaluate_(gpa, binary.right, env, objects);

            switch (binary.operator.tag) {
                .equal => return Value.Boolean.init(left.equal(right)),
                .not_equal => return Value.Boolean.init(!left.equal(right)),
                else => {},
            }

            const left_number = left.asNumber();
            const right_number = right.asNumber();

            if (left_number == null or right_number == null) {
                const operation, const preposition = switch (binary.operator.tag) {
                    .plus => .{ "add", "to" },
                    .minus => .{ "subtract", "from" },
                    .star => .{ "multiply", "with" },
                    .slash => .{ "divide", "by" },
                    else => unreachable,
                };
                log.err("can not {s} {f} {s} {f}\n", .{
                    operation,
                    left.tag(),
                    preposition,
                    right.tag(),
                });
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
            const scope = try Value.Closure.init(gpa, function, env);
            try objects.append(gpa, Object{ .value = scope });
            return scope;
        },
        .apply => |apply| {
            var function = try evaluate_(gpa, apply.function, env, objects);
            const argument = try evaluate_(gpa, apply.argument, env, objects);

            return switch (function) {
                .closure => |closure| {
                    var scope_owned: bool = false;
                    var scope = try Environment.init(gpa, closure.env);
                    errdefer if (!scope_owned) scope.deinitSelf(gpa);

                    try scope.define(gpa, closure.parameter, argument);
                    try objects.append(gpa, Object{ .env = scope });
                    scope_owned = true;

                    const body = try closure.body.clone(gpa);
                    try objects.append(gpa, Object{ .node = body });
                    return try evaluate_(gpa, body, scope, objects);
                },
                .builtin => |builtin| {
                    const result = try builtin.function(argument, env, builtin.capture_env);
                    defer function.deinit(gpa);
                    return result;
                },
                else => {
                    log.err("can not apply {f} to {f}\n", .{ apply.function, apply.argument });
                    return error.NotCallable;
                },
            };
        },
        .binding => |binding| {
            var scope_owned: bool = false;
            var scope = try Environment.init(gpa, env);
            errdefer if (!scope_owned) scope.deinitSelf(gpa);

            const name = binding.name.lexeme;
            try scope.define(gpa, name, Value.init());

            const value = switch (binding.value.tag()) {
                .function => try evaluate_(gpa, binding.value, scope, objects),
                else => try evaluate_(gpa, binding.value, env, objects),
            };

            try scope.bind(name, value);

            try objects.append(gpa, Object{ .env = scope });
            scope_owned = true;

            return try evaluate_(gpa, binding.body, scope, objects);
        },
        .selection => |selection| {
            const condition = try evaluate_(gpa, selection.condition, env, objects);
            const consequent = selection.consequent;
            const alternate = selection.alternate;

            if (condition.asBoolean()) |boolean| {
                return if (boolean)
                    evaluate_(gpa, consequent, env, objects)
                else
                    evaluate_(gpa, alternate, env, objects);
            } else {
                log.err("{f} is not a boolean\n", .{condition});
                return error.NotABoolean;
            }
        },
    };
}

const testing = std.testing;
const ta = testing.allocator;
const expect = testing.expect;
const expectError = testing.expectError;

fn runTest(gpa: Allocator, node: *Node, expected: Value) !void {
    var env = try Environment.init(gpa, null);
    defer env.deinitAll(gpa);

    var objects: ArrayList(Object) = .empty;
    defer {
        var i: usize = 0;
        while (i < objects.items.len) : (i += 1) {
            objects.items[i].deinit(gpa);
        }
        objects.deinit(gpa);
    }

    const actual = try evaluate(gpa, node, env, &objects);

    expect(expected.equal(actual)) catch |err| {
        log.err("expected {f} but got {f}\n", .{ expected, actual });
        return err;
    };
}

test "empty" {
    const ast = try Node.Program.init(ta, null);
    defer ast.deinit(ta);

    const expected = Value.init();
    try runTest(ta, ast, expected);
}

test "number" {
    // 123
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Primary.init(ta, Token.init(.number, input, "123")),
    );
    defer ast.deinit(ta);
    const expected = Value.Number.init(123);

    try runTest(ta, ast, expected);
}

test "apply" {
    // (λx. x) 123
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Application.init(
            ta,
            try Node.Function.init(
                ta,
                Token.init(.identifier, input, "x"),
                try Node.Primary.init(ta, Token.init(.identifier, input, "x")),
            ),
            try Node.Primary.init(ta, Token.init(.number, input, "123")),
        ),
    );
    defer ast.deinit(ta);
    const expected = Value.Number.init(123);

    try runTest(ta, ast, expected);
}

test "return" {
    // (λx. 999) 123
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Application.init(
            ta,
            try Node.Function.init(
                ta,
                Token.init(.identifier, input, "x"),
                try Node.Primary.init(ta, Token.init(.number, input, "999")),
            ),
            try Node.Primary.init(ta, Token.init(.number, input, "123")),
        ),
    );
    defer ast.deinit(ta);
    const expected = Value.Number.init(999);

    try runTest(ta, ast, expected);
}

test "shadowing" {
    // (λx. (λx. x) 2) 1
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Application.init(
            ta,
            try Node.Function.init(
                ta,
                Token.init(.identifier, input, "x"),
                try Node.Application.init(
                    ta,
                    try Node.Function.init(
                        ta,
                        Token.init(.identifier, input, "x"),
                        try Node.Primary.init(ta, Token.init(.identifier, input, "x")),
                    ),
                    try Node.Primary.init(ta, Token.init(.number, input, "2")),
                ),
            ),
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(2);
    try runTest(ta, ast, expected);
}

test "closure" {
    // (λx. (λy. x)) -1 -2
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Application.init(
            ta,
            try Node.Application.init(
                ta,
                try Node.Function.init(
                    ta,
                    Token.init(.identifier, input, "x"),
                    try Node.Function.init(
                        ta,
                        Token.init(.identifier, input, "y"),
                        try Node.Primary.init(ta, Token.init(.identifier, input, "x")),
                    ),
                ),
                try Node.Primary.init(ta, Token.init(.number, input, "-1")),
            ),
            try Node.Primary.init(ta, Token.init(.number, input, "-2")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(-1);
    try runTest(ta, ast, expected);
}

test "binding" {
    // let one = 1 in one
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binding.init(
            ta,
            Token.init(.identifier, input, "one"),
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
            try Node.Primary.init(ta, Token.init(.identifier, input, "one")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(1);
    try runTest(ta, ast, expected);
}

test "binding recursive binding for non-function" {
    // let x = x in x
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binding.init(
            ta,
            Token.init(.identifier, input, "x"),
            try Node.Primary.init(ta, Token.init(.identifier, input, "x")),
            try Node.Primary.init(ta, Token.init(.identifier, input, "x")),
        ),
    );
    defer ast.deinit(ta);

    var env = try Environment.init(ta, null);
    defer env.deinitAll(ta);

    var objects: ArrayList(Object) = .empty;
    defer {
        var i: usize = 0;
        while (i < objects.items.len) : (i += 1) {
            objects.items[i].deinit(ta);
        }
        objects.deinit(ta);
    }

    try expectError(error.NotDefined, evaluate(ta, ast, env, &objects));
}

test "binding recursive nested" {
    // let one = 1 in let two = two in one two
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binding.init(
            ta,
            Token.init(.identifier, input, "one"),
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
            try Node.Binding.init(
                ta,
                Token.init(.identifier, input, "two"),
                try Node.Primary.init(ta, Token.init(.identifier, input, "two")),
                try Node.Application.init(
                    ta,
                    try Node.Primary.init(ta, Token.init(.identifier, input, "one")),
                    try Node.Primary.init(ta, Token.init(.identifier, input, "two")),
                ),
            ),
        ),
    );
    defer ast.deinit(ta);

    var env = try Environment.init(ta, null);
    defer env.deinitAll(ta);

    var objects: ArrayList(Object) = .empty;
    defer {
        var i: usize = 0;
        while (i < objects.items.len) : (i += 1) {
            objects.items[i].deinit(ta);
        }
        objects.deinit(ta);
    }

    try expectError(error.NotDefined, evaluate(ta, ast, env, &objects));
}

test "evaluate equality" {
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binary.init(
            ta,
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
            Token.init(.equal, input, "=="),
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Boolean.init(true);
    try runTest(ta, ast, expected);
}

test "evaluate inequality" {
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binary.init(
            ta,
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
            Token.init(.not_equal, input, "!="),
            try Node.Primary.init(ta, Token.init(.number, input, "2")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Boolean.init(true);
    try runTest(ta, ast, expected);
}

test "literals" {
    // if null then true else false
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Selection.init(
            ta,
            try Node.Primary.init(ta, Token.init(.null, input, "null")),
            try Node.Primary.init(ta, Token.init(.true, input, "true")),
            try Node.Primary.init(ta, Token.init(.false, input, "false")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Boolean.init(false);
    try runTest(ta, ast, expected);
}

test "let nested" {
    // let one = (\z. 1) in
    //   let two = (\w. one w) in
    //     one two
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binding.init(
            ta,
            Token.init(.identifier, input, "one"),
            try Node.Function.init(
                ta,
                Token.init(.identifier, input, "z"),
                try Node.Primary.init(ta, Token.init(.number, input, "1")),
            ),
            try Node.Binding.init(
                ta,
                Token.init(.identifier, input, "two"),
                try Node.Function.init(
                    ta,
                    Token.init(.identifier, input, "w"),
                    try Node.Application.init(
                        ta,
                        try Node.Primary.init(ta, Token.init(.identifier, input, "one")),
                        try Node.Primary.init(ta, Token.init(.identifier, input, "w")),
                    ),
                ),
                try Node.Application.init(
                    ta,
                    try Node.Primary.init(ta, Token.init(.identifier, input, "one")),
                    try Node.Primary.init(ta, Token.init(.identifier, input, "two")),
                ),
            ),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(1);
    try runTest(ta, ast, expected);
}

test "multiplication precedence over addition" {
    // 1 + 2 * 3 = 7
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binary.init(
            ta,
            try Node.Primary.init(ta, Token.init(.number, input, "1")),
            Token.init(.plus, input, "+"),
            try Node.Binary.init(
                ta,
                try Node.Primary.init(ta, Token.init(.number, input, "2")),
                Token.init(.star, input, "*"),
                try Node.Primary.init(ta, Token.init(.number, input, "3")),
            ),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(7);
    try runTest(ta, ast, expected);
}

test "arithmetic expression" {
    // (1 + 2) * 3 = 9
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binary.init(
            ta,
            try Node.Binary.init(
                ta,
                try Node.Primary.init(ta, Token.init(.number, input, "1")),
                Token.init(.plus, input, "+"),
                try Node.Primary.init(ta, Token.init(.number, input, "2")),
            ),
            Token.init(.star, input, "*"),
            try Node.Primary.init(ta, Token.init(.number, input, "3")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(9);
    try runTest(ta, ast, expected);
}

test "recursive call" {
    // fn called with true -> returns false
    // fn called with false -> returns 1234

    // (one liner)
    // let fn = \var. if var then fn false else 1234 in fn false

    // let fn = \var. if var then
    //     fn false
    // else
    //     1234
    // in
    //     fn false
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binding.init(
            ta,
            Token.init(.identifier, input, "fn"),
            try Node.Function.init(
                ta,
                Token.init(.identifier, input, "var"),
                try Node.Selection.init(
                    ta,
                    try Node.Primary.init(ta, Token.init(.identifier, input, "var")),
                    try Node.Application.init(
                        ta,
                        try Node.Primary.init(ta, Token.init(.identifier, input, "fn")),
                        try Node.Primary.init(ta, Token.init(.false, input, "false")),
                    ),
                    try Node.Primary.init(ta, Token.init(.number, input, "1234")),
                ),
            ),
            try Node.Application.init(
                ta,
                try Node.Primary.init(ta, Token.init(.identifier, input, "fn")),
                try Node.Primary.init(ta, Token.init(.false, input, "false")),
            ),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(1234);
    try runTest(ta, ast, expected);
}

test "factorial" {
    // let fact = \n. if n == 0 then 1 else n * fact (n - 1) in fact 5
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Binding.init(
            ta,
            Token.init(.identifier, input, "fact"),
            try Node.Function.init(
                ta,
                Token.init(.identifier, input, "n"),
                try Node.Selection.init(
                    ta,
                    try Node.Binary.init(
                        ta,
                        try Node.Primary.init(ta, Token.init(.identifier, input, "n")),
                        Token.init(.equal, input, "=="),
                        try Node.Primary.init(ta, Token.init(.number, input, "0")),
                    ),
                    try Node.Primary.init(ta, Token.init(.number, input, "1")),
                    try Node.Binary.init(
                        ta,
                        try Node.Primary.init(ta, Token.init(.identifier, input, "n")),
                        Token.init(.star, input, "*"),
                        try Node.Application.init(
                            ta,
                            try Node.Primary.init(ta, Token.init(.identifier, input, "fact")),
                            try Node.Binary.init(
                                ta,
                                try Node.Primary.init(ta, Token.init(.identifier, input, "n")),
                                Token.init(.minus, input, "-"),
                                try Node.Primary.init(ta, Token.init(.number, input, "1")),
                            ),
                        ),
                    ),
                ),
            ),
            try Node.Application.init(
                ta,
                try Node.Primary.init(ta, Token.init(.identifier, input, "fact")),
                try Node.Primary.init(ta, Token.init(.number, input, "5")),
            ),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Number.init(120);
    try runTest(ta, ast, expected);
}
