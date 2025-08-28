const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;
const log = std.log.scoped(.allocator);

pub fn LoggingAllocator() type {
    return struct {
        const Self = @This();

        child_allocator: Allocator,

        pub fn init(child_allocator: Allocator) Self {
            return Self{ .child_allocator = child_allocator };
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
            const result = self.child_allocator.rawAlloc(len, ptr_align, ret_addr);

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
            self.child_allocator.rawFree(buf, buf_align, ret_addr);
        }

        fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.child_allocator.vtable.remap(self.child_allocator.ptr, memory, alignment, new_len, ret_addr);
        }

        fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.child_allocator.vtable.resize(self.child_allocator.ptr, memory, alignment, new_len, ret_addr);
        }
    };
}

pub fn init(child_allocator: Allocator) LoggingAllocator() {
    return LoggingAllocator().init(child_allocator);
}
