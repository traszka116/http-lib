const std = @import("std");
const net = std.net;
const mem = std.mem;

const http = @import("http.zig");
const types = http.types;
const Request = http.Request;
const Response = http.Response;

pub const Server = struct {
    listener: net.Server,
    context: *anyopaque,
    response: *const fn (*anyopaque, Request, mem.Allocator) anyerror!types.Connection,
    allocator: mem.Allocator,
    buffer_size: usize,

    pub fn init(address: net.Address, allocator: mem.Allocator, buffer_size: usize, response: *const fn (*anyopaque, Request, mem.Allocator) anyerror!types.Connection, context: *anyopaque) !Server {
        const server = try address.listen(.{ .reuse_address = true });
        return .{
            .listener = server,
            .context = context,
            .response = response,
            .allocator = allocator,
            .buffer_size = buffer_size,
        };
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit();
    }

    pub fn run(self: *Server) !void {
        const buf = try self.allocator.alloc(u8, self.buffer_size);
        while (true) {
            const connection = self.listener.accept() catch continue;
            var stream = connection.stream;
            while (handleRequest(self, buf, stream)) |conn| {
                if(conn == .close) {
                    stream.close();
                    break;

                }
            } else |err| {
                std.log.err("{}", .{err});
            }
        }
    }

    fn handleRequest(server: *Server, buff: []u8, stream: net.Stream) !types.Connection {
        const len = try stream.read(buff);
        const bytes = buff[0..len];
        var req = try Request.parse(bytes, server.allocator, stream.writer().any());
        errdefer req.deinit();
        defer req.deinit();
        return server.response(server.context, req, server.allocator);
    }
};
