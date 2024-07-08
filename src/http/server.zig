const std = @import("std");
const net = std.net;
const mem = std.mem;
const fmt = std.fmt;

const http = @import("http.zig");
const types = http.types;
const Request = http.Request;
const Response = http.Response;

pub const _Server = struct {
    listener: net.Server,
    context: *anyopaque,
    arena: std.heap.ArenaAllocator,
    allocator: mem.Allocator,
    respond: *const fn (*_Server, Request) anyerror!void,
    max_request_size: usize,

    pub fn deinit(self: *_Server) void {
        self.listener.deinit();
        self.arena.deinit();
    }

    pub fn run(self: *_Server) !void {
        var buffer: [4096]u8 = undefined;
        while (true) {
            const connection = self.listener.accept() catch continue;
            var stream = connection.stream;
            while (true) {
                const len = try stream.read(&buffer);
                const bytes = buffer[0..len];
                var req = Request.parse(bytes, self.allocator, stream.writer().any()) catch |err| switch (err) {
                    // in case of inner allocation failing drop request
                    mem.Allocator.Error.OutOfMemory => {
                        stream.close();
                        continue;
                    },
                    // in case of invalid request, request is set to be invalid
                    else => invalid_req: {
                        var r: Request = undefined;
                        r.is_valid = false;
                        break :invalid_req r;
                    },
                };

                defer req.deinit();
                // tries to create a response, if cannot drops the request

                self.respond(self, req) catch {
                    stream.close();
                    continue;
                };

                if (req.connection == .Close) {
                    stream.close();
                    break;
                }
            }
        }
    }
};

pub const Server = struct {
    listener: net.Server,
    context: *anyopaque,
    response: *const fn (*Server, Request) anyerror!types.Connection,
    allocator: mem.Allocator,
    buffer_size: usize,

    pub fn init(address: net.Address, allocator: mem.Allocator, buffer_size: usize, response: *const fn (*Server, Request) anyerror!types.Connection, context: *anyopaque) !Server {
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
        _ = self;
    }

    pub fn run(self: *Server) !void {
        const buf = try self.allocator.alloc(u8, self.buffer_size);
        while (true) {
            const connection = self.listener.accept() catch continue;
            var stream = connection.stream;
            while (handleRequest(self, buf, stream)) |conn| {
                if (conn == .Close) {
                    stream.close();
                    break;
                }
            } else |err| std.log.err("{}", .{err});
        }
    }

    fn handleRequest(server: *Server, buff: []u8, stream: net.Stream) !types.Connection {
        const len = try stream.read(buff);
        const bytes = buff[0..len];
        var req = try Request.parse(bytes, server.allocator, stream.writer().any());
        errdefer req.deinit();
        defer req.deinit();
        return try server.response(server, req);
    }
};
