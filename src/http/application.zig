const std = @import("std");
const mem = std.mem;
const Route = @import("./router.zig").Route;
const Request = @import("./request.zig").Request;
const Response = @import("./response.zig").Response;

pub const Application = struct {
    router: std.StringHashMap(Route),
    not_found: Route,
    server: std.net.Server,
    allocator: mem.Allocator,
    request_buffer_size: usize = 4096,

    pub fn addRoute(self: *Application, path: []const u8, route: Route) !void {
        try self.router.put(path, route);
    }

    pub fn addRoutes(self: *Application, routes: []const struct { path: []const u8, route: Route }) !void {
        try self.router.ensureUnusedCapacity(routes.len);
        for (routes) |route| {
            self.router.putAssumeCapacity(route.path, route.route);
        }
    }

    pub fn init(server: std.net.Server, allocator: mem.Allocator, not_found: Route) Application {
        return Application{
            .server = server,
            .router = std.StringHashMap(Route).init(allocator),
            .not_found = not_found,
            .allocator = allocator,
        };
    }

    pub fn run(self: *Application) !void {
        const buffer = try self.allocator.alloc(u8, self.request_buffer_size);
        while (true) {
            const connection = self.server.accept() catch |err| {
                std.log.err("error: {}", .{err});
                continue;
            };
            const stream = connection.stream;
            handleConnection(self, stream, buffer) catch |err| {
                std.log.err("error: {}", .{err});
            };
        }
    }

    fn handleConnection(self: *Application, stream: std.net.Stream, buffer: []u8) !void {
        var response = Response.init(.@"HTTP/1.0", .{ .normal = .OK }, .@"Keep-Alive", &.{}, null, stream.writer().any());
        errdefer stream.close();
        defer stream.close();
        while (response.connection == .@"Keep-Alive") {
            const len = stream.read(buffer) catch |err| {
                std.log.err("error: {}", .{err});
                return error.UnexpectedEOF;
            };

            const request = Request.parse(buffer[0..len], self.allocator) catch |err| {
                std.log.err("error: {}", .{err});
                return error.InvalidRequest;
            };

            response = Response.init(request.version, .{ .normal = .OK }, request.connection, &.{}, null, stream.writer().any());
            const route = self.router.get(request.url) orelse self.not_found;
            const handler = route.dispatch(request.method);
            try handler(@ptrCast(route.context), request, &response);
        }
    }
};
