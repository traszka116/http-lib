const std = @import("std");
const fmt = std.fmt;
const ascii = std.ascii;

const testing = std.testing;

fn hash(str: []const u8) usize {
    var h: usize = 0;
    for (str, 0..) |c, i| {
        h +%= @as(usize, c) * 31 ^ (str.len - i);
    }
    return h;
}

pub fn hashUpper(str: []const u8) usize {
    var h: usize = 0;
    for (str, 0..) |c, i| {
        h +%= @as(usize, ascii.toUpper(c)) * 31 ^ (str.len - i);
    }
    return h;
}

pub const Method = enum(usize) {
    OPTIONS = hash("OPTIONS"),
    GET = hash("GET"),
    HEAD = hash("HEAD"),
    POST = hash("POST"),
    PUT = hash("PUT"),
    PATCH = hash("PATCH"),
    DELETE = hash("DELETE"),
    TRACE = hash("TRACE"),
    CONNECT = hash("CONNECT"),

    pub fn format(self: Method, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        _ = try writer.write(switch (self) {
            .OPTIONS => "OPTIONS",
            .GET => "GET",
            .HEAD => "HEAD",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .TRACE => "TRACE",
            .CONNECT => "CONNECT",
            .PATCH => "CONNECT",
        });
    }

    pub fn parse(str: []const u8) ?Method {
        const h = hash(str);
        return switch (h) {
            hash("OPTIONS") => .OPTIONS,
            hash("GET") => .GET,
            hash("HEAD") => .HEAD,
            hash("POST") => .POST,
            hash("PUT") => .PUT,
            hash("DELETE") => .DELETE,
            hash("TRACE") => .TRACE,
            hash("CONNECT") => .CONNECT,
            else => null,
        };
    }

    test {
        try testing.expectEqual(.OPTIONS, parse("OPTIONS"));
        try testing.expectEqual(.GET, parse("GET"));
        try testing.expectEqual(.HEAD, parse("HEAD"));
        try testing.expectEqual(.POST, parse("POST"));
        try testing.expectEqual(.PUT, parse("PUT"));
        try testing.expectEqual(.DELETE, parse("DELETE"));
        try testing.expectEqual(.TRACE, parse("TRACE"));
        try testing.expectEqual(.CONNECT, parse("CONNECT"));
    }
};

pub const Version = enum(usize) {
    @"HTTP/1.0" = hash("HTTP/1.0"),
    @"HTTP/1.1" = hash("HTTP/1.1"),

    pub fn format(self: Version, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        _ = try writer.write(@tagName(self));
    }

    pub fn parse(str: []const u8) ?Version {
        return switch (hash(str)) {
            hash("HTTP/1.0") => .@"HTTP/1.0",
            hash("HTTP/1.1") => .@"HTTP/1.1",
            else => null,
        };
    }

    test {
        try testing.expectEqual(.@"HTTP/1.0", parse("HTTP/1.0"));
        try testing.expectEqual(.@"HTTP/1.1", parse("HTTP/1.1"));
        try testing.expectEqual(null, parse("HTT"));
    }
};

pub const Connection = enum(usize) {
    @"Keep-Alive" = hash("KEEP ALIVE"),
    Close = hash("CLOSE"),

    pub fn format(self: Connection, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        _ = try writer.write(switch (self) {
            .@"Keep-Alive" => "Keep Alive",
            else => "Close",
        });
    }
    pub fn parse(str: []const u8) ?Connection {
        return switch (hashUpper(str)) {
            hash("KEEP ALIVE") => .@"Keep-Alive",
            hash("CLOSE") => .Close,
            else => return null,
        };
    }

    test {
        try testing.expectEqual(.Close, parse("Close"));
        try testing.expectEqual(.Close, parse("ClosE"));
        try testing.expectEqual(.Close, parse("CloSE"));
        try testing.expectEqual(.Close, parse("CLOse"));
        try testing.expectEqual(.@"Keep-Alive", parse("Keep Alive"));
        try testing.expectEqual(.@"Keep-Alive", parse("KEEp AlIve"));
        try testing.expectEqual(.@"Keep-Alive", parse("keeP ALIvE"));
        try testing.expectEqual(.@"Keep-Alive", parse("kEEp AlivE"));
        try testing.expectEqual(null, parse("CLOseD"));
        try testing.expectEqual(null, parse("Keep_Alive"));
        try testing.expectEqual(null, parse("Alive"));
    }
};

pub const StatusCode = enum(u10) {
    Continue = 100,
    @"Switching Protocols" = 101,
    Processing = 102,
    @"Early Hints" = 103,
    OK = 200,
    Created = 201,
    Accepted = 202,
    @"Non-Authoritative Information" = 203,
    @"No Content" = 204,
    @"Reset Content" = 205,
    @"Partial Content" = 206,
    @"Multi-Status" = 207,
    @"Already Reported" = 208,
    @"IM Used" = 226,
    @"Multiple Choices" = 300,
    @"Moved Permanently" = 301,
    Found = 302,
    @"See Other" = 303,
    @"Not Modified" = 304,
    @"Use Proxy" = 305,
    @"Temporary Redirect" = 307,
    @"Permanent Redirect" = 308,
    @"Bad Request" = 400,
    Unauthorized = 401,
    @"Payment Required" = 402,
    Forbidden = 403,
    @"Not Found" = 404,
    @"Method Not Allowed" = 405,
    @"Not Acceptable" = 406,
    @"Proxy Authentication Required" = 407,
    @"Request Timeout" = 408,
    Conflict = 409,
    Gone = 410,
    @"Length Required" = 411,
    @"Precondition Failed" = 412,
    @"Payload Too Large" = 413,
    @"URI Too Long" = 414,
    @"Unsupported Media Type" = 415,
    @"Range Not Satisfiable" = 416,
    @"Expectation Failed" = 417,
    @"I'm a teapot" = 418,
    @"Misdirected Request" = 421,
    @"Unprocessable Content" = 422,
    Locked = 423,
    @"Failed Dependency" = 424,
    @"Too Early" = 425,
    @"Upgrade Required" = 426,
    @"Precondition Required" = 428,
    @"Too Many Requests" = 429,
    @"Request Header Fields Too Large" = 431,
    @"Unavailable For Legal Reasons" = 451,
    @"Internal Server Error" = 500,
    @"Not Implemented" = 501,
    @"Bad Gateway" = 502,
    @"Service Unavailable" = 503,
    @"Gateway Timeout" = 504,
    @"HTTP Version Not Supported" = 505,
    @"Variant Also Negotiates" = 506,
    @"Insufficient Storage" = 507,
    @"Loop Detected" = 508,
    @"Not Extended" = 510,
    @"Network Authentication Required" = 511,
    _,

    pub fn format(self: StatusCode, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d} {s}", .{ @intFromEnum(self), @tagName(self) });
    }

    pub const Custom = struct {
        code: u10,
        reason: []const u8,

        pub fn init(code: u10, reason: []const u8) Custom {
            return Custom{ .code = code, .reason = reason };
        }

        pub fn format(self: Custom, comptime _: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{d} {s}", .{ self.code, self.reason });
        }
    };

    pub fn cast(self: StatusCode) Custom {
        return Custom{ .code = @intFromEnum(self), .reason = @tagName(self) };
    }
};

test "Request" {
    _ = Method;
    _ = Version;
    _ = Connection;
}
