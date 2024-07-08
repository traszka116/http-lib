const std = @import("std");
const enums = std.enums;

const http = @import("http.zig");
const types = http.types;
const Request = http.Request;
const Response = http.Response;

pub const Handler = fn (*http.Server, Request) anyerror!types.Connection;

pub const Route = struct {
    get: ?*const Handler = null,
    post: ?*const Handler = null,
    put: ?*const Handler = null,
    delete: ?*const Handler = null,
    patch: ?*const Handler = null,
    default: *const Handler,
    pub fn dispatch(self: Route, method: types.Method) *const Handler {
        return switch (method) {
            .GET => self.get orelse self.default,
            .POST => self.post orelse self.default,
            .PATCH => self.patch orelse self.default,
            .PUT => self.put orelse self.default,
            .DELETE => self.delete orelse self.default,
            else => self.default,
        };
    }
};

pub const Router = struct {
    routes: std.StringHashMap(Route),
    notFound: *const Handler,
    context: *anyopaque,

    pub fn init(allocator: std.mem.Allocator, notFound: *const Handler, context: *anyopaque) Router {
        return Router{
            .routes = std.StringHashMap(Route).init(allocator),
            .notFound = notFound,
            .context = context,
        };
    }

    pub fn set(self: *Router, path: []const u8, route: Route) !void {
        try self.routes.put(path, route);
    }

    fn dispatch(self: Router, request: Request) *const Handler {
        const route = self.routes.get(request.url) orelse return self.notFound;
        return route.dispatch(request.method);
    }

    pub fn handle(server: *http.Server, request: Request) anyerror!types.Connection {
        var router: *Router = @ptrCast(@alignCast(server.context));
        const handler = router.dispatch(request);
        return handler(server, request);
    }
};
