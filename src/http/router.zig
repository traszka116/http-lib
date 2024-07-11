const http = @import("http.zig");
const Method = http.types.Method;
const Connection = http.types.Connection;

const std = @import("std");
const mem = std.mem;
const StringHashMap = std.StringHashMap;

pub const Handler = fn (*anyopaque, http.Request, mem.Allocator) anyerror!Connection;

pub const Route = struct {
    context: *anyopaque,
    get: ?*const Handler = null,
    post: ?*const Handler = null,
    put: ?*const Handler = null,
    delete: ?*const Handler = null,
    patch: ?*const Handler = null,
    default: *const Handler,
    pub fn dispatch(self: Route, method: Method) *const Handler {
        return switch (method) {
            .GET => self.get orelse self.default,
            .POST => self.post orelse self.default,
            .PATCH => self.patch orelse self.default,
            .PUT => self.put orelse self.default,
            .DELETE => self.delete orelse self.default,
            else => self.default,
        };
    }

    pub fn from(some_ptr: anytype) Route {
        if (@typeInfo(@TypeOf(some_ptr)) != .Pointer) {
            @compileError("Expected a pointer.");
        }

        if (!@hasDecl(@TypeOf(some_ptr.*), "default")) {
            @compileError("No default handler found.");
        }

        return Route{
            .context = @ptrCast(some_ptr),
            .default = @ptrCast(&@TypeOf(some_ptr.*).default),
            .get = if (@hasDecl(@TypeOf(some_ptr.*), "get") and @TypeOf(&@TypeOf(some_ptr.*).get) == fn (*anyopaque, http.Request, mem.Allocator) anyerror!Connection) @ptrCast(&@TypeOf(some_ptr.*).get) else null,
            .post = if (@hasDecl(@TypeOf(some_ptr.*), "post") and @TypeOf(&@TypeOf(some_ptr.*).post) == fn (*anyopaque, http.Request, mem.Allocator) anyerror!Connection) @ptrCast(&@TypeOf(some_ptr.*).post) else null,
            .put = if (@hasDecl(@TypeOf(some_ptr.*), "put") and @TypeOf(&@TypeOf(some_ptr.*).put) == fn (*anyopaque, http.Request, mem.Allocator) anyerror!Connection) @ptrCast(&@TypeOf(some_ptr.*).put) else null,
            .delete = if (@hasDecl(@TypeOf(some_ptr.*), "delete") and @TypeOf(&@TypeOf(some_ptr.*).delete) == fn (*anyopaque, http.Request, mem.Allocator) anyerror!Connection) @ptrCast(&@TypeOf(some_ptr.*).delete) else null,
            .patch = if (@hasDecl(@TypeOf(some_ptr.*), "patch") and @TypeOf(&@TypeOf(some_ptr.*).patch) == fn (*anyopaque, http.Request, mem.Allocator) anyerror!Connection) @ptrCast(&@TypeOf(some_ptr.*).patch) else null,
        };
    }
};

pub const Router = struct {
    map: StringHashMap(Route),
    /// takes in empty context, request and allocator
    notFound: *const Handler,

    pub fn init(not_found: *const Handler, allocator: mem.Allocator, routes: []const struct { []const u8, Route }) !Router {
        var map = StringHashMap(Route).init(allocator);
        try map.ensureTotalCapacity(@truncate(routes.len));

        for (routes) |route| {
            map.putAssumeCapacity(route[0], route[1]);
        }

        return Router{
            .map = map,
            .notFound = not_found,
        };
    }

    pub fn deinit(self: *Router, allocator: mem.Allocator) void {
        self.map.deinit(allocator);
    }

    pub fn addRoute(self: *Router, path: []const u8, route: Route) !void {
        try self.map.put(path, route);
    }

    pub fn handle(self: *anyopaque, request: http.Request, allocator: mem.Allocator) anyerror!Connection {
        const router: *Router = @ptrCast(self);
        const route = router.map.get(request.url) orelse return router.notFound(@constCast(@ptrCast(&.{})), request, allocator);
        const handler = route.dispatch(request.method);
        return handler(self, request, allocator);
    }
};
