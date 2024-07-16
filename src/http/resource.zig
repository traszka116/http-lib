const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const Vector = std.ArrayList;

const Route = @import("./router.zig").Route;
const Response = @import("./response.zig").Response;
const Request = @import("./request.zig").Request;
const http = @import("./types.zig");

pub const Resource = struct {
    path: []const u8,
    mime: http.ContentType,
    file: fs.File,

    pub usingnamespace Route.methodNotAllowed(@This());

    fn hash(str: []const u8) usize {
        var h: usize = 0;
        for (str, 0..) |c, i| {
            h +%= @as(usize, std.ascii.toUpper(c)) * 31 ^ (str.len - i);
        }
        return h;
    }

    fn content_type_from_extension(extension: []const u8) http.ContentType {
        const h = hash(extension);

        return switch (h) {
            hash("html") => .html,
            hash("javascript") => .javascript,
            hash("css") => .css,
            hash("xml") => .xml,
            hash("json") => .json,
            hash("text") => .text,
            hash("pdf") => .pdf,
            hash("jpg") => .jpg,
            hash("png") => .png,
            hash("gif") => .gif,
            hash("svg") => .svg,
            hash("mp3") => .mp3,
            hash("mp4") => .mp4,
            else => .{ .other = "application/octet-stream" },
        };
    }

    pub fn init(path: []const u8, dir: fs.Dir, allocator: mem.Allocator) !Resource {
        const file = try dir.openFile(path, .{});
        const index = mem.lastIndexOfScalar(u8, path, '.') orelse path.len;
        const extension = path[index..];
        const mime = content_type_from_extension(extension);
        const stats = try file.stat();

        const content = try file.readToEndAlloc(allocator, stats.size);
        errdefer allocator.free(content);

        const path_dupe = try allocator.dupe(u8, path);
        errdefer allocator.free(path_dupe);

        return Resource{
            .path = path_dupe,
            .mime = mime,
            .content = content,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Resource) void {
        self.allocator.free(self.content);
        self.allocator.free(self.path);
    }

    pub fn changeAllocator(self: *Resource, allocator: mem.Allocator) !void {
        const new_content = try allocator.dupe(u8, self.content);
        errdefer allocator.free(new_content);
        const new_path = try allocator.dupe(u8, self.path);
        errdefer allocator.free(new_path);
    }

    pub fn get(self: *Resource, req: Request, res: *Response) anyerror!void {
        res.connection = req.connection;
        res.status_code = .OK;
        res.content = .{ .content_type = self.mime, .body = self.content };
        res.version = req.version;
        try res.send();
    }
};

pub fn mapDirectory(dir: fs.Dir, allocator: mem.Allocator) !struct { []Resource, std.heap.ArenaAllocator } {
    var walk = try dir.walk(allocator);

    var arena = std.heap.ArenaAllocator.init(allocator);
    const alloc = arena.allocator();
    errdefer _ = arena.reset(.free_all);

    var resources = Vector(Resource).init(allocator);

    while (walk.next()) |entry_opt| {
        if (entry_opt == null) break;
        const entry = entry_opt.?;
        if (entry.kind != .file) continue;
        const path = entry.path;
        const resource = try Resource.init(path, dir, alloc);
        try resources.append(resource);
    } else |err| return err;

    return .{ resources.toOwnedSlice(), arena };
}
