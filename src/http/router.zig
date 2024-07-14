const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const types = @import("types.zig");
const Response = @import("response.zig").Response;
const Request = @import("request.zig").Request;

const Context = *anyopaque;
const Handler = fn (Context, Request, *Response) anyerror!void;

fn TransformHandler(handler: anytype, comptime T: type) Handler {
    return struct {
        fn func(context: Context, req: Request, res: *Response) anyerror!void {
            const ctx: *T = @ptrCast(@alignCast(context));
            return @call(.always_inline, handler, .{ ctx, req, res });
        }
    }.func;
}

pub const Route = struct {
    context: Context,
    default: *const Handler,
    get: ?*const Handler = null,
    post: ?*const Handler = null,
    put: ?*const Handler = null,
    patch: ?*const Handler = null,
    delete: ?*const Handler = null,
    options: ?*const Handler = null,
    head: ?*const Handler = null,
    trace: ?*const Handler = null,
    connect: ?*const Handler = null,

    pub fn dispatch(self: Route, method: types.Method) *const Handler {
        return switch (method) {
            .OPTIONS => self.options,
            .GET => self.get,
            .HEAD => self.head,
            .POST => self.post,
            .PUT => self.put,
            .PATCH => self.patch,
            .DELETE => self.delete,
            .TRACE => self.trace,
            .CONNECT => self.connect,
        } orelse self.default;
    }

    pub fn from(context: anytype) Route {
        if (@typeInfo(@TypeOf(context)) != .Pointer) {
            @compileError("Context must be a pointer type");
        }

        const contextType = @TypeOf(context.*);
        if (!@hasDecl(contextType, "default")) {
            @compileError("Context must have a default handler");
        }

        const contextHandlerType = fn (*contextType, Request, *Response) anyerror!void;
        if (@TypeOf(&contextType.default) != *const contextHandlerType) {
            @compileError(fmt.comptimePrint("Default handler must be of type :'{}', has type: '{}'", .{ *const contextHandlerType, @TypeOf(&contextType.default) }));
        }

        const defaultHandler = &TransformHandler(contextType.default, contextType);
        const getHandler = if (@hasDecl(contextType, "get") and @TypeOf(&contextType.get) == *const contextHandlerType) &TransformHandler(contextType.get, contextType) else null;
        const postHandler = if (@hasDecl(contextType, "post") and @TypeOf(&contextType.post) == *const contextHandlerType) &TransformHandler(contextType.post, contextType) else null;
        const putHandler = if (@hasDecl(contextType, "put") and @TypeOf(&contextType.put) == *const contextHandlerType) &TransformHandler(contextType.put, contextType) else null;
        const patchHandler = if (@hasDecl(contextType, "patch") and @TypeOf(&contextType.patch) == *const contextHandlerType) &TransformHandler(contextType.patch, contextType) else null;
        const deleteHandler = if (@hasDecl(contextType, "delete") and @TypeOf(&contextType.delete) == *const contextHandlerType) &TransformHandler(contextType.delete, contextType) else null;
        const optionsHandler = if (@hasDecl(contextType, "options") and @TypeOf(&contextType.options) == *const contextHandlerType) &TransformHandler(contextType.options, contextType) else null;
        const headHandler = if (@hasDecl(contextType, "head") and @TypeOf(&contextType.head) == *const contextHandlerType) &TransformHandler(contextType.head, contextType) else null;
        const traceHandler = if (@hasDecl(contextType, "trace") and @TypeOf(&contextType.trace) == *const contextHandlerType) &TransformHandler(contextType.trace, contextType) else null;
        const connectHandler = if (@hasDecl(contextType, "connect") and @TypeOf(&contextType.connect) == *const contextHandlerType) &TransformHandler(contextType.connect, contextType) else null;

        return Route{
            .context = context,
            .default = defaultHandler,
            .get = getHandler,
            .post = postHandler,
            .put = putHandler,
            .patch = patchHandler,
            .delete = deleteHandler,
            .options = optionsHandler,
            .head = headHandler,
            .trace = traceHandler,
            .connect = connectHandler,
        };
    }

    pub fn unimplemented(comptime T: type) type {
        return struct {
            pub fn default(context: *T, req: Request, res: *Response) anyerror!void {
                _ = context;
                res.connection = .Close;
                res.status_code = .{ .normal = .@"Not Implemented" };
                res.content = .{ .content_type = .html, .body = "This route is not implemented yet" };
                res.version = req.version;
                try res.send();
            }
        };
    }

    pub fn notFound(comptime T: type) type {
        return struct {
            pub fn default(context: *T, req: Request, res: *Response) anyerror!void {
                _ = context;
                res.connection = .Close;
                res.status_code = .{ .normal = .@"Not Found" };
                res.content = .{ .content_type = .html, .body = "This route was not found" };
                res.version = req.version;
                try res.send();
            }
        };
    }

    pub fn methodNotAllowed(comptime T: type) type {
        return struct {
            pub fn default(context: *T, req: Request, res: *Response) anyerror!void {
                _ = context;
                res.connection = .Close;
                res.status_code = .{ .normal = .@"Method Not Allowed" };
                res.content = .{ .content_type = .html, .body = "This method is not allowed on this route" };
                res.version = req.version;
                try res.send();
            }
        };
    }
};

pub const Application = struct {
    router: std.StringHashMap(Route),
    not_found: Route,
    server: std.net.Server,
    allocator: mem.Allocator,
    request_buffer_size: usize = 4096,

    pub fn addRoute(self: *Application, path: []const u8, route: Route) !void {
        try self.router.put(path, route);
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
