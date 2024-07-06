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

const ContentInfo = struct {
    content_type: []const u8,
    body: []const u8,
};

const Header = struct {
    key: []const u8,
    value: []const u8,
};

const StatusCode = union(enum) {
    normal: Status,
    custom: CustomStatus,
    pub fn format(self: StatusCode, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        return switch (self) {
            inline else => |e| fmt.format(writer, "{}", .{e}),
        };
    }
    pub fn code(self: StatusCode) Status {
        return switch (self) {
            .normal => |n| @intFromEnum(n),
            .custom => |c| c.code,
        };
    }
    pub fn name(self: StatusCode) []const u8 {
        return switch (self) {
            .normal => |n| @tagName(n),
            .custom => |c| c.name,
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

    pub fn init(
        version: Version,
        status: StatusCode,
        headers: []Header,
        content: ?ContentInfo,
    ) Response {
        return Response{
            .version = version,
            .status_code = status,
            .connection = Connection.Close,
            .headers = headers,
            .content = content,
        };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
        self.* = undefined;
    }

    pub fn format(self: Response, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        try fmt.format(writer, "{s} {} {s}\r\n", .{ self.version, self.status_code.code(), self.status_code.name() });
        try fmt.format(writer, "Connection: {s}\r\n", .{self.connection});
        if (self.content) |content| {
            try fmt.format(writer, "Content-Type: {s}", .{content.content_type});
            try fmt.format(writer, "Content-Length: {}", .{content.body.len});
        }
        for (self.headers) |header| {
            try fmt.format(writer, "{s}: {s}\r\n", .{ header.key, header.value });
        }
        try writer.write("\r\n");
        if (self.content) |content| {
            try writer.write(content.body);
        }
        try writer.write("\r\n");
    }
};
