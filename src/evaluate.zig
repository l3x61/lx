const std = @import("std");

const Environment = @import("Environment.zig");
const Node = @import("node.zig").Node;
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;
const Gc = @import("Gc.zig");

const log = std.log.scoped(.eval);

pub fn evaluate(
    node: *Node,
    gc: *Gc,
    env: *Environment,
) !Value {
    return eval(node, gc, env);
}

fn eval(
    node: *Node,
    gc: *Gc,
    env: *Environment,
) !Value {
    const gpa = gc.allocator();
    return switch (node.*) {
        .program => |program| {
            const expression = program.expression orelse return Value.init();
            return try eval(expression, gc, env);
        },
        .primary => |primary| {
            const operand = primary.operand;
            return switch (operand.tag) {
                .true => Value.Boolean.init(true),
                .false => Value.Boolean.init(false),
                .number => try Value.Number.parse(operand.lexeme),
                .string => block: {
                    var string = try Value.String.init(gpa, operand.lexeme[1 .. operand.lexeme.len - 1]);
                    errdefer string.deinit(gpa);
                    try gc.track(string);
                    break :block string;
                },
                .identifier => try env.get(primary.operand.lexeme),
                else => unreachable,
            };
        },
        .binary => |binary| {
            const left = try eval(binary.left, gc, env);
            const right = try eval(binary.right, gc, env);

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
                log.warn("can not {s} {f} {s} {f}\n", .{
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
                        log.warn("division by 0 in expression {f}\n", .{node});
                        return error.DivisionByZero;
                    }
                    return Value.Number.init(lnum / rnum);
                },
                else => unreachable,
            };

            return Value.Number.init(result);
        },
        .function => |function| {
            var closure = try Value.Closure.init(gpa, function, env);
            errdefer closure.deinit(gpa);
            try gc.track(closure);
            return closure;
        },
        .application => |application| {
            var function = try eval(application.function, gc, env);
            const argument = try eval(application.argument, gc, env);

            return switch (function) {
                .closure => |closure| {
                    var scope_tracked: bool = false;
                    var scope = try Environment.init(gpa, closure.env);
                    errdefer if (!scope_tracked) scope.deinit();

                    try scope.bind(closure.parameter, argument);
                    try gc.track(scope);
                    scope_tracked = true;

                    return try eval(closure.body, gc, scope);
                },
                .native => |native| {
                    const result = try native.function(argument, env, native.capture_env);
                    return result;
                },
                else => {
                    log.warn("can not apply {f}:{f} to {f}:{f}\n", .{
                        application.function,
                        function.tag(),
                        application.argument,
                        argument.tag(),
                    });
                    return error.NotCallable;
                },
            };
        },
        .binding => |binding| {
            var scope_tracked: bool = false;

            var scope = try Environment.init(gpa, env);
            errdefer if (!scope_tracked) scope.deinit();

            const name = binding.name.lexeme;
            try scope.bind(name, null);

            const value = switch (binding.value.tag()) {
                .function => try eval(binding.value, gc, scope),
                else => try eval(binding.value, gc, env),
            };

            try scope.set(name, value);

            try gc.track(scope);
            scope_tracked = true;

            return try eval(binding.body, gc, scope);
        },
        .selection => |selection| {
            const condition = try eval(selection.condition, gc, env);
            const consequent = selection.consequent;
            const alternate = selection.alternate;

            if (condition.asBoolean()) |boolean| {
                return if (boolean)
                    eval(consequent, gc, env)
                else
                    eval(alternate, gc, env);
            } else {
                log.warn("{f} is not a boolean\n", .{condition});
                return error.NotABoolean;
            }
        },
    };
}

const Allocator = std.mem.Allocator;
const testing = std.testing;
const ta = testing.allocator;
const expect = testing.expect;
const expectError = testing.expectError;

fn runTest(node: *Node, expected: Value) !void {
    var gc = try Gc.init(ta);
    defer gc.deinit();

    const gc_gpa = gc.allocator();

    var env_tracked = false;
    var env = try Environment.init(gc_gpa, null);
    errdefer if (!env_tracked) env.deinitAll();

    try gc.track(env);
    env_tracked = true;

    const actual = try evaluate(node, &gc, env);

    expect(expected.equal(actual)) catch |err| {
        log.warn("expected {f} but got {f}\n", .{ expected, actual });
        return err;
    };
}

test "empty" {
    const ast = try Node.Program.init(ta, null);
    defer ast.deinit(ta);

    const expected = Value.init();
    try runTest(ast, expected);
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

    try runTest(ast, expected);
}

test "application" {
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

    try runTest(ast, expected);
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

    try runTest(ast, expected);
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
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

    var gc = try Gc.init(ta);
    defer gc.deinit();

    const gc_gpa = gc.allocator();

    var env_tracked = false;
    var env = try Environment.init(gc_gpa, null);
    errdefer if (!env_tracked) env.deinitAll();

    try gc.track(env);
    env_tracked = true;

    try expectError(error.NotDefined, evaluate(ast, &gc, env));
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

    var gc = try Gc.init(ta);
    defer gc.deinit();

    const gc_gpa = gc.allocator();

    var env_tracked = false;
    var env = try Environment.init(gc_gpa, null);
    errdefer if (!env_tracked) env.deinitAll();

    try gc.track(env);
    env_tracked = true;

    try expectError(error.NotDefined, evaluate(ast, &gc, env));
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
}

test "literals" {
    // if true then true else false
    const input = "";
    const ast = try Node.Program.init(
        ta,
        try Node.Selection.init(
            ta,
            try Node.Primary.init(ta, Token.init(.true, input, "true")),
            try Node.Primary.init(ta, Token.init(.true, input, "true")),
            try Node.Primary.init(ta, Token.init(.false, input, "false")),
        ),
    );
    defer ast.deinit(ta);

    const expected = Value.Boolean.init(true);
    try runTest(ast, expected);
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
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
    try runTest(ast, expected);
}
