const std = @import("std");

pub fn Matrix(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []T,
        rows: usize,
        cols: usize,

        pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Self {
            return Self{
                .data = try allocator.alloc(T, rows * cols),
                .rows = rows,
                .cols = cols,
            };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            allocator.free(self.data);
        }

        pub fn set(self: *Self, row: usize, col: usize, value: T) void {
            self.data[row * self.cols + col] = value;
        }

        pub fn get(self: *const Self, row: usize, col: usize) T {
            return self.data[row * self.cols + col];
        }

        pub fn add(allocator: ?std.mem.Allocator, left: *const Self, right: *const Self, out: *Self) !void {
            if (allocator != null) {
                out.* = try Self.init(allocator.?, left.rows, left.cols);
            }

            if (left.rows != right.rows or left.cols != right.cols or 
                left.rows != out.rows or left.cols != out.cols) {
                return std.debug.panic("Matrix dimensions do not match", .{});
            }

            const size: usize = left.rows * left.cols;
            const supported = supported_numeric_type(T);
            switch (supported) {
                SupportedNumericType.BuiltInNumeric => {
                    for (0..size) |i| {
                        out.data[i] = left.data[i] + right.data[i];
                    }
                },
                SupportedNumericType.BuiltinBool => {
                    @compileError("Addition is not supported for bool");
                },
                SupportedNumericType.Custom => {
                    for (0..size) |i| {
                        T.add(null, &left.data[i], &right.data[i], &out.data[i]);
                    }
                },
                SupportedNumericType.Unsupported => {
                    unreachable;
                },
            }

            return;
        }
    };
}

// Wether the type is builtin numeric, bool, custom or unsupported.
pub inline fn supported_numeric_type(comptime T: type) SupportedNumericType {
    const info = @typeInfo(T);
    const name = @typeName(T);

    return switch (info) {
        .Int, .Float => SupportedNumericType.BuiltInNumeric,
        .Bool => SupportedNumericType.BuiltinBool,
        else => {
            if (std.mem.eql(u8, name, "BigInt") or 
                std.mem.eql(u8, name, "Fraction") or
                std.mem.eql(u8, name, "Complex") or
                std.mem.eql(u8, name, "Expression"))
            {
                SupportedNumericType.Custom;
            } else {
                unreachable;
            }
        },
    };
}

const SupportedNumericType = enum {
    BuiltInNumeric, // i8, i16, i32, i64, u8, u16, u32, u64, f32, f64, f128
    BuiltinBool, // bool
    Custom, // BigInt, Fraction, Complex, Expression
    Unsupported,
};