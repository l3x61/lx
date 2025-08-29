const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const String = @This();

array: ArrayList(u8),

pub const empty = String{ .array = ArrayList(u8).empty };

pub inline fn initSlice(ator: Allocator, slice: []const u8) !String {
    var string = String.empty;
    try string.appendSlice(ator, slice);
    return string;
}

pub inline fn initPrint(ator: Allocator, comptime fmt: []const u8, args: anytype) !void {
    var string = String.init();
    try string.print(ator, fmt, args);
    return string;
}

pub inline fn deinit(self: *String, ator: Allocator) void {
    self.array.deinit(ator);
}

pub inline fn clone(self: *String, ator: Allocator) !String {
    return String.initSlice(ator, self.getSlice());
}

pub inline fn getSlice(self: *String) []u8 {
    return self.array.items;
}

pub inline fn appendSlice(self: *String, ator: Allocator, slice: []const u8) !void {
    return self.array.appendSlice(ator, slice);
}

pub inline fn print(self: *String, ator: Allocator, comptime fmt: []const u8, args: anytype) !void {
    return self.array.print(ator, fmt, args);
}

test "init" {
    const a = testing.allocator;
    var string = String.empty;
    defer string.deinit(a);
}

test "initSlice" {
    const a = testing.allocator;
    const literal = "Hello World!";

    var string = try String.initSlice(a, literal);
    defer string.deinit(a);

    try testing.expectEqualStrings(string.array.items, literal);
}

test "initPrint" {
    const a = testing.allocator;
    const literal = "Hello World!";

    var string = try String.initSlice(a, literal);
    defer string.deinit(a);

    try testing.expectEqualStrings(string.getSlice(), literal);
}

test "clone" {
    const a = testing.allocator;
    const literal = "Hello World!";

    var string = try String.initSlice(a, literal);
    defer string.deinit(a);

    var new = try string.clone(a);
    defer new.deinit(a);

    try testing.expectEqualStrings(string.getSlice(), literal);
    try testing.expectEqualStrings(new.getSlice(), literal);
}
