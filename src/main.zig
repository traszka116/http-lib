const std = @import("std");
const net = std.net;
const heap = std.heap;

const http = @import("http/http.zig");

pub fn main() !void {
    var arena = heap.ArenaAllocator.init(heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var server = net.Server{ .listen_address = net.Address.initIp4([_]u8{ 127, 0, 0, 1 }, 80), .stream = undefined };
    defer server.deinit();

    const connection = try server.accept();
    defer connection.stream.close();
    const reader = connection.stream.reader();
    const req = try reader.readAllAlloc(allocator, 4096);
    var request = try http.Request.parse(req, allocator);
    defer request.deinit();
    std.log.debug("{}", .{request});
}
