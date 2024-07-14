const std = @import("std");
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;
const Map = std.ArrayHashMap;

const types = @import("types.zig");
const Connection = types.Connection;
const Method = types.Method;
const Version = types.Version;

const ihash = types.hashUpper;
const ieql = std.ascii.eqlIgnoreCase;

const HeaderContext = struct {
    pub fn hash(_: @This(), s: []const u8) u32 {
        return @truncate(ihash(s));
    }

    pub fn eql(_: @This(), a: []const u8, b: []const u8, _: usize) bool {
        return ieql(a, b);
    }
};

const testing = std.testing;
const Headers = Map([]const u8, []const u8, HeaderContext, true);
pub const Request = struct {
    method: Method,
    version: Version,
    url: []const u8,
    query: ?[]const u8,
    connection: Connection,
    /// managed key-value store of headers
    headers: Headers,

    content_type: ?[]const u8,
    body: ?[]const u8,
    is_valid: bool = true,


    pub fn parse(bytes: []const u8, allocator: mem.Allocator) !Request {
        var iter = mem.splitSequence(u8, bytes, "\r\n");
        const head_line = iter.next() orelse return error.RequestInvalid;
        var head_iterator = mem.splitScalar(u8, head_line, ' ');
        const method_str = head_iterator.next() orelse return error.NoMethod;

        const url_str = head_iterator.next() orelse return error.NoUrl;

        const version_str = head_iterator.next() orelse return error.NoVersion;

        const method = Method.parse(method_str) orelse return error.InvalidMethod;
        const version = Version.parse(version_str) orelse return error.InvalidVersion;

        const url_end = mem.indexOfScalar(u8, url_str, '?') orelse url_str.len;
        const resource = url_str[0..url_end];
        const query: ?[]const u8 = if (url_end == url_str.len or url_end == url_str.len - 1) null else url_str[url_end + 1 ..];

        var request = Request{
            .method = method,
            .version = version,
            .url = resource,
            .query = query,
            .connection = undefined,
            .headers = Headers.init(allocator),
            .body = null,
            .content_type = null,
        };
        errdefer request.headers.deinit();

        var content_lenght: ?usize = null;

        while (iter.next()) |line| {
            if (mem.eql(u8, line, "")) {
                break;
            }
            const end_of_name = mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = line[0..end_of_name];
            const value = std.mem.trim(u8, line[end_of_name + 1 .. line.len], " \t");
            try request.headers.put(key, value);

            const key_hash = ihash(key);
            if (key_hash == comptime ihash("Connection")) {
                request.connection = Connection.parse(value) orelse Connection.Close;
            } else if (key_hash == comptime ihash("Content-Type")) {
                request.content_type = value;
            } else if (key_hash == comptime ihash("Content-Length")) {
                content_lenght = std.fmt.parseInt(usize, value, 10) catch null;
            }
        }

        if (version == .@"HTTP/1.0") {
            request.connection = .Close;
        }

        const read_body = switch (method) {
            .POST, .PUT, .PATCH => true,
            else => false,
        };

        if (!read_body) {
            return request;
        }

        const body_start = iter.next();
        if (body_start == null) return request;

        const body_start_index: usize = @intFromPtr(body_start.?.ptr) - @intFromPtr(bytes.ptr);
        const end_index = if (content_lenght) |len| @min(body_start_index + len, bytes.len) else bytes.len;
        request.body = bytes[body_start_index..end_index];

        return request;
    }

    pub fn deinit(self: *Request) void {
        self.headers.deinit();
    }

    test {
        const request_bytes = "GET /hi HTTP/1.0\r\n" ++
            "content-tYpe: text/plain\r\n" ++
            "content-Length:10\r\n" ++
            "connectioN:\t keep-alive \r\n\r\n";
        var request = try parse(request_bytes, std.testing.allocator, io.null_writer.any());
        defer request.deinit();
        try testing.expectEqual(request.body, null);
        try testing.expectEqualSlices(u8, request.url, "/hi");
        try testing.expectEqual(request.version, .@"HTTP/1.0");
    }
};

test "request" {
    _ = Request;
}
