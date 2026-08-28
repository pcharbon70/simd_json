const std = @import("std");

/// Instantiate the ownership layer with declarations translated from the
/// canonical C header. The Zigler root and native tests each supply that same
/// header module, so this file never duplicates C constants or layouts.
pub fn Implementation(comptime c: type) type {
    return struct {
        pub const required_padding_bytes: usize = @intCast(c.SIMD_JSON_REQUIRED_PADDING);
        pub const input_alignment_bytes: usize = required_padding_bytes;
        pub const input_alignment: std.mem.Alignment = .fromByteUnits(input_alignment_bytes);

        pub const Diagnostics = struct {
            native_code: ?i32,
            byte_offset: ?u64,
        };

        /// Closed adaptation of the private C status domain. Unknown numeric
        /// values become internal failures rather than entering the BEAM.
        pub const NativeStatus = union(enum) {
            ok,
            invalid_json: Diagnostics,
            invalid_utf8: Diagnostics,
            unexpected_eof: Diagnostics,
            out_of_memory: Diagnostics,
            invalid_argument: Diagnostics,
            internal_failure: Diagnostics,
        };

        pub const Lifecycle = enum(u8) {
            open,
            closing,
            closed,
        };

        /// Native storage embedded in the opaque BEAM resource. The C handles
        /// are private fields and this module has no term-encoding helpers.
        pub const DocumentState = struct {
            allocator: ?std.mem.Allocator,
            padded_input: ?[]align(input_alignment_bytes) u8,
            logical_length: usize,
            parser_handle: ?*c.simd_json_parser,
            document_handle: ?*c.simd_json_document,
            lifecycle: std.atomic.Value(u8),
            generation: std.atomic.Value(u64),
            admitted_operations: std.atomic.Value(usize),

            /// Establish a fully destructible state before any fallible work.
            pub fn empty() DocumentState {
                return .{
                    .allocator = null,
                    .padded_input = null,
                    .logical_length = 0,
                    .parser_handle = null,
                    .document_handle = null,
                    .lifecycle = .init(@intFromEnum(Lifecycle.closed)),
                    .generation = .init(0),
                    .admitted_operations = .init(0),
                };
            }

            pub fn lifecycleState(self: *const DocumentState) Lifecycle {
                return @enumFromInt(self.lifecycle.load(.acquire));
            }

            pub fn hasOwnedNativeState(self: *const DocumentState) bool {
                return self.padded_input != null or
                    self.parser_handle != null or
                    self.document_handle != null;
            }
        };

        pub fn adaptStatus(status: c.simd_json_status) NativeStatus {
            const diagnostics = Diagnostics{
                .native_code = if (status.native_code == c.SIMD_JSON_NATIVE_CODE_UNAVAILABLE)
                    null
                else
                    status.native_code,
                .byte_offset = if (status.byte_offset == c.SIMD_JSON_BYTE_OFFSET_UNAVAILABLE)
                    null
                else
                    status.byte_offset,
            };

            return switch (status.code) {
                c.SIMD_JSON_STATUS_OK => .ok,
                c.SIMD_JSON_STATUS_INVALID_JSON => .{ .invalid_json = diagnostics },
                c.SIMD_JSON_STATUS_INVALID_UTF8 => .{ .invalid_utf8 = diagnostics },
                c.SIMD_JSON_STATUS_UNEXPECTED_EOF => .{ .unexpected_eof = diagnostics },
                c.SIMD_JSON_STATUS_OUT_OF_MEMORY => .{ .out_of_memory = diagnostics },
                c.SIMD_JSON_STATUS_INVALID_ARGUMENT => .{ .invalid_argument = diagnostics },
                c.SIMD_JSON_STATUS_INTERNAL_FAILURE => .{ .internal_failure = diagnostics },
                else => .{ .internal_failure = diagnostics },
            };
        }

        comptime {
            if (@sizeOf(c.simd_json_status_code) != @sizeOf(i32))
                @compileError("C status code width differs from Zig i32");
            if (@typeInfo(c.simd_json_status_code).int.signedness != .signed)
                @compileError("C status code must remain signed");
            if (@sizeOf(c.simd_json_status) != 16)
                @compileError("C status layout changed");
            if (@alignOf(c.simd_json_status) != @alignOf(u64))
                @compileError("C status alignment changed");
            if (@offsetOf(c.simd_json_status, "code") != 0 or
                @offsetOf(c.simd_json_status, "native_code") != 4 or
                @offsetOf(c.simd_json_status, "byte_offset") != 8)
                @compileError("C status field offsets changed");

            const status_values = [_]c.simd_json_status_code{
                c.SIMD_JSON_STATUS_OK,
                c.SIMD_JSON_STATUS_INVALID_JSON,
                c.SIMD_JSON_STATUS_INVALID_UTF8,
                c.SIMD_JSON_STATUS_UNEXPECTED_EOF,
                c.SIMD_JSON_STATUS_OUT_OF_MEMORY,
                c.SIMD_JSON_STATUS_INVALID_ARGUMENT,
                c.SIMD_JSON_STATUS_INTERNAL_FAILURE,
            };
            for (status_values, 0..) |value, index| {
                for (status_values[index + 1 ..]) |other| {
                    if (value == other) @compileError("C status values must be unique");
                }
            }

            if (required_padding_bytes == 0 or !std.math.isPowerOfTwo(input_alignment_bytes))
                @compileError("the pinned padding-derived input alignment must be a non-zero power of two");
        }
    };
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership
