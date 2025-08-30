const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const log = std.log.scoped(.ator);

pub fn LoggingAllocator() type {
    return struct {
        const Self = @This();

        ator: Allocator,

        pub fn init(child_ator: Allocator) Self {
            return Self{ .ator = child_ator };
        }

        pub fn allocator(self: *Self) Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .free = free,
                    .resize = resize,
                    .remap = remap,
                },
            };
        }

        fn alloc(ctx: *anyopaque, len: usize, ptr_align: Alignment, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            const result = self.ator.rawAlloc(len, ptr_align, ret_addr);

            if (result) |ptr| {
                log.debug("allocate {} bytes at 0x{x}\n", .{ len, @intFromPtr(ptr) });
            } else {
                log.err("failed to allocate {} bytes\n", .{len});
            }

            return result;
        }

        fn free(ctx: *anyopaque, buf: []u8, buf_align: Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            log.debug("free {} bytes at 0x{x}\n", .{ buf.len, @intFromPtr(buf.ptr) });
            self.ator.rawFree(buf, buf_align, ret_addr);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.ator.vtable.remap(self.ator.ptr, memory, alignment, new_len, ret_addr);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.ator.vtable.resize(self.ator.ptr, memory, alignment, new_len, ret_addr);
        }
    };
}

pub fn init(child_ator: Allocator) LoggingAllocator() {
    return LoggingAllocator().init(child_ator);
}
