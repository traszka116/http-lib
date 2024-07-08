const std = @import("std");
const mem = std.mem;
const io = std.io;
const fmt = std.fmt;
const net = std.net;

const types = @import("types.zig");
const Connection = types.Connection;
const Method = types.Method;
const Version = types.Version;
const Status = types.StatusCode;
const CustomStatus = Status.Custom;

const ContentType = types.ContentType;

const ContentInfo = struct {
    content_type: ContentType,
    body: []const u8,
};

pub const Header = struct {
    key: []const u8,
    value: []const u8,
};

pub const StatusCode = union(enum) {
    normal: Status,
    custom: CustomStatus,
    pub fn format(self: StatusCode, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        return switch (self) {
            inline else => |e| fmt.format(writer, "{}", .{e}),
        };
    }
    pub fn code(self: StatusCode) Status {
        return switch (self) {
            .normal => |n| n,
            .custom => |c| @enumFromInt(c.code),
        };
    }
    pub fn name(self: StatusCode) []const u8 {
        return switch (self) {
            .normal => |n| @tagName(n),
            .custom => |c| c.reason,
        };
    }
};

pub const Response = struct {
    version: Version,
    status_code: StatusCode,
    connection: Connection,
    // managed key-value store of headers
    headers: std.StringHashMap([]const u8),
    content: ?ContentInfo,

    pub fn init(version: Version, status: StatusCode, connection: Connection, headers: []const Header, content: ?ContentInfo, allocator: mem.Allocator) !Response {
        var header_map = std.StringHashMap([]const u8).init(allocator);
        for (headers) |header| {
            try header_map.put(header.key, header.value);
        }
        return Response{
            .version = version,
            .status_code = status,
            .connection = connection,
            .headers = header_map,
            .content = content,
        };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
        self.* = undefined;
    }

    pub fn format(self: Response, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        try fmt.format(writer, "{s} {s}\r\n", .{ self.version, self.status_code });
        try fmt.format(writer, "Connection: {s}\r\n", .{self.connection});
        if (self.content) |content| {
            try fmt.format(writer, "Content-Type: {s}\r\n", .{content.content_type.to_str()});
            try fmt.format(writer, "Content-Length: {}\r\n", .{content.body.len});
        }
        var headers = self.headers.iterator();

        while (headers.next()) |header| {
            try fmt.format(writer, "{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
        }
        _ = try writer.write("\r\n");
        if (self.content) |content| {
            _ = try writer.write(content.body);
        }
        _ = try writer.write("\r\n");
    }
};
