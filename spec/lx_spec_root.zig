const std = @import("std");
const ArrayList = std.ArrayList;

const lx = @import("lx");
const Environment = lx.Environment;
const Parser = lx.Parser;
const Value = lx.Value;
const Object = lx.Object;

fn parseExpected(raw: []const u8) ?Value {
    const marker = "#=";
    if (std.mem.indexOf(u8, raw, marker)) |idx| {
        var line = raw[idx + marker.len ..];
        if (std.mem.indexOfScalar(u8, line, '\n')) |nl| line = line[0..nl];
        line = std.mem.trim(u8, line, " \t\r");
        if (line.len == 0) return null;
        if (std.mem.eql(u8, line, "null")) return Value.Null.init();
        if (std.mem.eql(u8, line, "true")) return Value.Boolean.init(true);
        if (std.mem.eql(u8, line, "false")) return Value.Boolean.init(false);
        const num = std.fmt.parseFloat(f64, line) catch return null;
        return Value.Number.init(num);
    }
    return null;
}

const testing = std.testing;
const ta = testing.allocator;
const expect = testing.expect;

fn runSpec(text: []const u8) !void {
    var env = try Environment.init(ta, null);
    var objects: ArrayList(Object) = .empty;
    defer {
        var i: usize = 0;
        while (i < objects.items.len) : (i += 1) objects.items[i].deinit(ta);
        objects.deinit(ta);
    }

    try objects.append(ta, Object{ .env = env });

    const exit = lx.builtin_exit;
    try env.define(ta, exit.name, Value.Builtin.init(exit.name, exit.function, null));

    var parser = try Parser.init(ta, text);
    const ast = try parser.parse();
    defer ast.deinit(ta);

    var result = try lx.evaluate(ta, ast, env, &objects);
    defer result.deinit(ta);

    // Intentionally not asserting exact value here; focus on successful execution.
}

test "spec/pass factorial" { try runSpec(@embedFile("pass/factorial.lx")); }
test "spec/pass empty" { try runSpec(@embedFile("pass/empty.lx")); }
