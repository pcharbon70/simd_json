const std = @import("std");

/// Owned target serialization and opaque cursor lifetime for private ABI v3.
/// The public stream term, caller output keys, owner PID, and raw BEAM terms do
/// not enter these types. A BEAM cursor resource retains the parent separately.
pub fn Implementation(comptime c: type, comptime projection: type) type {
    return struct {
        const Self = @This();
        const test_build = @hasDecl(c, "simd_json_test_stream_summary_read") and
            @hasDecl(c, "simd_json_test_stream_accounting_snapshot");

        pub const Segment = union(enum) {
            object_key: []const u8,
            array_index: u64,
        };

        pub const Target = struct {
            segments: []const Segment,
        };

        pub const Limits = struct {
            rows: u64,
            encoded_bytes: u64,
        };

        pub const BuildError = error{
            OutOfMemory,
            InvalidTarget,
            InvalidPlan,
            NativeFailure,
        };

        pub const FailureCode = enum {
            invalid_json,
            invalid_utf8,
            unexpected_eof,
            out_of_memory,
            invalid_argument,
            internal_failure,
            missing_field,
            index_out_of_bounds,
            incorrect_type,
            number_out_of_range,
            cursor_consumed,
            cancelled,
            batch_too_large,
            cursor_state,
        };

        pub const Failure = struct {
            code: FailureCode,
            native_code: ?i32,
            byte_offset: ?u64,
            output_slot: ?u32,
            array_index: ?u64,
        };

        const SerializedTarget = struct {
            allocator: std.mem.Allocator,
            segments: []c.simd_json_projection_segment,
            key_bytes: []u8,

            fn init(
                allocator: std.mem.Allocator,
                target: Target,
            ) BuildError!SerializedTarget {
                if (target.segments.len > c.SIMD_JSON_MAX_DEPTH)
                    return error.InvalidTarget;

                var key_byte_count: usize = 0;
                for (target.segments) |segment| switch (segment) {
                    .object_key => |key| {
                        if (!std.unicode.utf8ValidateSlice(key))
                            return error.InvalidTarget;
                        key_byte_count = std.math.add(
                            usize,
                            key_byte_count,
                            key.len,
                        ) catch return error.InvalidTarget;
                    },
                    .array_index => {},
                };

                _ = std.math.cast(u64, target.segments.len) orelse
                    return error.InvalidTarget;
                _ = std.math.cast(u64, key_byte_count) orelse
                    return error.InvalidTarget;

                const segments = allocator.alloc(
                    c.simd_json_projection_segment,
                    target.segments.len,
                ) catch return error.OutOfMemory;
                errdefer allocator.free(segments);
                const key_bytes = allocator.alloc(u8, key_byte_count) catch
                    return error.OutOfMemory;
                errdefer allocator.free(key_bytes);

                var key_cursor: usize = 0;
                for (target.segments, segments) |segment, *serialized| {
                    switch (segment) {
                        .object_key => |key| {
                            const key_offset = std.math.cast(u64, key_cursor) orelse
                                return error.InvalidTarget;
                            const key_length = std.math.cast(u64, key.len) orelse
                                return error.InvalidTarget;
                            @memcpy(key_bytes[key_cursor..][0..key.len], key);
                            key_cursor += key.len;
                            serialized.* = .{
                                .tag = c.SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY,
                                .reserved = 0,
                                .key_offset = key_offset,
                                .key_length = key_length,
                                .array_index = 0,
                            };
                        },
                        .array_index => |index| serialized.* = .{
                            .tag = c.SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX,
                            .reserved = 0,
                            .key_offset = 0,
                            .key_length = 0,
                            .array_index = index,
                        },
                    }
                }

                std.debug.assert(key_cursor == key_byte_count);
                return .{
                    .allocator = allocator,
                    .segments = segments,
                    .key_bytes = key_bytes,
                };
            }

            fn descriptor(self: *const SerializedTarget) c.simd_json_stream_target {
                return .{
                    .segments = if (self.segments.len == 0) null else self.segments.ptr,
                    .segment_count = @intCast(self.segments.len),
                    .key_bytes = if (self.key_bytes.len == 0) null else self.key_bytes.ptr,
                    .key_bytes_length = @intCast(self.key_bytes.len),
                };
            }

            fn deinit(self: *SerializedTarget) void {
                self.allocator.free(self.key_bytes);
                self.allocator.free(self.segments);
                self.* = undefined;
            }
        };

        pub const OwnedCursor = struct {
            handle: ?*c.simd_json_stream_cursor = null,
            parent_generation: u64 = 0,
            output_slots: usize = 0,
            limits: Limits = .{ .rows = 0, .encoded_bytes = 0 },

            pub fn empty() OwnedCursor {
                return .{};
            }

            /// Transfers the plan to C at the constructor's documented
            /// ownership point. On any failure after transfer the C rollback
            /// has already destroyed it, so the Zig plan wrapper is cleared.
            pub fn init(
                allocator: std.mem.Allocator,
                document: ?*c.simd_json_document,
                plan: *projection.OwnedPlan,
                target: Target,
                limits: Limits,
                parent_generation: u64,
            ) BuildError!OwnedCursor {
                if (document == null or !plan.isAlive() or parent_generation == 0 or
                    limits.rows == 0 or limits.rows > c.SIMD_JSON_STREAM_MAX_BATCH_SIZE or
                    limits.encoded_bytes == 0 or
                    limits.encoded_bytes > c.SIMD_JSON_STREAM_MAX_BATCH_BYTES)
                    return error.InvalidTarget;

                var serialized = try SerializedTarget.init(allocator, target);
                defer serialized.deinit();
                var target_descriptor = serialized.descriptor();
                var config = c.simd_json_stream_cursor_config{
                    .projection_plan = plan.handle,
                    .row_limit = limits.rows,
                    .encoded_byte_limit = limits.encoded_bytes,
                    .parent_generation = parent_generation,
                    .reserved = 0,
                };
                var handle: ?*c.simd_json_stream_cursor = null;
                const output_slots = plan.output_slots;
                const status = c.simd_json_stream_cursor_create(
                    document,
                    &target_descriptor,
                    &config,
                    &handle,
                );

                if (config.projection_plan == null) {
                    plan.handle = null;
                    plan.output_slots = 0;
                } else {
                    plan.handle = config.projection_plan;
                }

                if (status.code != c.SIMD_JSON_STATUS_OK or handle == null) {
                    if (handle) |unexpected| c.simd_json_stream_cursor_destroy(unexpected);
                    return switch (status.code) {
                        c.SIMD_JSON_STATUS_OUT_OF_MEMORY => error.OutOfMemory,
                        c.SIMD_JSON_STATUS_INVALID_ARGUMENT => error.InvalidTarget,
                        else => error.NativeFailure,
                    };
                }
                if (config.projection_plan != null) {
                    c.simd_json_stream_cursor_destroy(handle.?);
                    return error.NativeFailure;
                }

                return .{
                    .handle = handle,
                    .parent_generation = parent_generation,
                    .output_slots = output_slots,
                    .limits = limits,
                };
            }

            pub fn deinit(self: *OwnedCursor) void {
                const handle = self.handle orelse return;
                self.handle = null;
                self.parent_generation = 0;
                self.output_slots = 0;
                self.limits = .{ .rows = 0, .encoded_bytes = 0 };
                c.simd_json_stream_cursor_destroy(handle);
            }

            pub fn isAlive(self: *const OwnedCursor) bool {
                return self.handle != null;
            }
        };

        pub const OwnedBatch = struct {
            allocator: std.mem.Allocator,
            rows: []c.simd_json_stream_row,
            slots: []c.simd_json_result_slot,
            copied_bytes: []u8,
            produced_rows: usize = 0,
            produced_slots: usize = 0,
            encoded_bytes: u64 = 0,
            done: bool = false,

            pub fn init(
                allocator: std.mem.Allocator,
                cursor: *const OwnedCursor,
            ) BuildError!OwnedBatch {
                if (!cursor.isAlive() or cursor.output_slots == 0)
                    return error.InvalidTarget;
                const row_count = std.math.cast(usize, cursor.limits.rows) orelse
                    return error.InvalidTarget;
                const slot_count = std.math.mul(
                    usize,
                    row_count,
                    cursor.output_slots,
                ) catch return error.InvalidTarget;
                const byte_count = std.math.cast(
                    usize,
                    cursor.limits.encoded_bytes,
                ) orelse return error.InvalidTarget;

                const rows = allocator.alloc(c.simd_json_stream_row, row_count) catch
                    return error.OutOfMemory;
                errdefer allocator.free(rows);
                const slots = allocator.alloc(c.simd_json_result_slot, slot_count) catch
                    return error.OutOfMemory;
                errdefer allocator.free(slots);
                const copied_bytes = allocator.alloc(u8, byte_count) catch
                    return error.OutOfMemory;
                errdefer allocator.free(copied_bytes);
                @memset(rows, std.mem.zeroes(c.simd_json_stream_row));
                @memset(slots, std.mem.zeroes(c.simd_json_result_slot));
                return .{
                    .allocator = allocator,
                    .rows = rows,
                    .slots = slots,
                    .copied_bytes = copied_bytes,
                };
            }

            pub fn deinit(self: *OwnedBatch) void {
                self.allocator.free(self.copied_bytes);
                self.allocator.free(self.slots);
                self.allocator.free(self.rows);
                self.* = undefined;
            }

            fn descriptor(self: *OwnedBatch) c.simd_json_stream_batch_storage {
                return .{
                    .rows = self.rows.ptr,
                    .row_capacity = @intCast(self.rows.len),
                    .slots = self.slots.ptr,
                    .slot_capacity = @intCast(self.slots.len),
                    .copied_bytes = self.copied_bytes.ptr,
                    .copied_byte_capacity = @intCast(self.copied_bytes.len),
                    .produced_rows = 0,
                    .produced_slots = 0,
                    .encoded_bytes = 0,
                    .done = c.SIMD_JSON_STREAM_NOT_DONE,
                    .reserved = 0,
                };
            }

            pub fn next(
                self: *OwnedBatch,
                cursor: *OwnedCursor,
            ) ?Failure {
                const handle = cursor.handle orelse return .{
                    .code = .cursor_state,
                    .native_code = null,
                    .byte_offset = null,
                    .output_slot = null,
                    .array_index = null,
                };
                var native = self.descriptor();
                const status = c.simd_json_stream_next_batch(handle, null, &native);
                self.produced_rows = @intCast(native.produced_rows);
                self.produced_slots = @intCast(native.produced_slots);
                self.encoded_bytes = native.encoded_bytes;
                self.done = native.done == c.SIMD_JSON_STREAM_DONE;
                if (status.code != c.SIMD_JSON_STATUS_OK) {
                    self.produced_rows = 0;
                    self.produced_slots = 0;
                    self.encoded_bytes = 0;
                    self.done = false;
                    return adaptFailure(status);
                }
                return null;
            }

            pub fn rowSlice(self: *const OwnedBatch) []const c.simd_json_stream_row {
                return self.rows[0..self.produced_rows];
            }

            pub fn slotSlice(self: *const OwnedBatch) []const c.simd_json_result_slot {
                return self.slots[0..self.produced_slots];
            }
        };

        pub fn adaptFailure(status: c.simd_json_stream_status) Failure {
            const code: FailureCode = switch (status.code) {
                c.SIMD_JSON_STATUS_INVALID_JSON => .invalid_json,
                c.SIMD_JSON_STATUS_INVALID_UTF8 => .invalid_utf8,
                c.SIMD_JSON_STATUS_UNEXPECTED_EOF => .unexpected_eof,
                c.SIMD_JSON_STATUS_OUT_OF_MEMORY => .out_of_memory,
                c.SIMD_JSON_STATUS_INVALID_ARGUMENT => .invalid_argument,
                c.SIMD_JSON_STATUS_MISSING_FIELD => .missing_field,
                c.SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS => .index_out_of_bounds,
                c.SIMD_JSON_STATUS_INCORRECT_TYPE => .incorrect_type,
                c.SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE => .number_out_of_range,
                c.SIMD_JSON_STATUS_CURSOR_CONSUMED => .cursor_consumed,
                c.SIMD_JSON_STATUS_CANCELLED => .cancelled,
                c.SIMD_JSON_STATUS_BATCH_TOO_LARGE => .batch_too_large,
                c.SIMD_JSON_STATUS_CURSOR_STATE => .cursor_state,
                else => .internal_failure,
            };
            return .{
                .code = code,
                .native_code = if (status.native_code == c.SIMD_JSON_NATIVE_CODE_UNAVAILABLE)
                    null
                else
                    status.native_code,
                .byte_offset = if (status.byte_offset == c.SIMD_JSON_BYTE_OFFSET_UNAVAILABLE)
                    null
                else
                    status.byte_offset,
                .output_slot = if (status.output_slot == c.SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE)
                    null
                else
                    status.output_slot,
                .array_index = if (status.array_index == c.SIMD_JSON_ARRAY_INDEX_UNAVAILABLE)
                    null
                else
                    status.array_index,
            };
        }

        pub const testing = if (test_build) struct {
            pub const Summary = struct {
                target_segments: u64,
                object_segments: u64,
                array_segments: u64,
                key_bytes: u64,
                row_limit: u64,
                encoded_byte_limit: u64,
                parent_generation: u64,
                current_row_index: u64,
                batch_sequence: u64,
                target_lookups: u64,
                projection_attempts: u64,
                committed_rows: u64,
                state: u32,
                owns_projection_plan: bool,
            };

            pub const Accounting = struct {
                live_cursors: u64,
                live_frames: u64,
                live_key_bytes: u64,
                live_owned_plans: u64,

                pub fn isQuiescent(self: Accounting) bool {
                    return self.live_cursors == 0 and self.live_frames == 0 and
                        self.live_key_bytes == 0 and self.live_owned_plans == 0;
                }
            };

            pub fn summary(cursor: *const OwnedCursor) ?Summary {
                const handle = cursor.handle orelse return null;
                var native: c.simd_json_test_stream_summary = undefined;
                if (c.simd_json_test_stream_summary_read(handle, &native) == 0)
                    return null;
                return .{
                    .target_segments = native.target_segments,
                    .object_segments = native.object_segments,
                    .array_segments = native.array_segments,
                    .key_bytes = native.key_bytes,
                    .row_limit = native.row_limit,
                    .encoded_byte_limit = native.encoded_byte_limit,
                    .parent_generation = native.parent_generation,
                    .current_row_index = native.current_row_index,
                    .batch_sequence = native.batch_sequence,
                    .target_lookups = native.target_lookups,
                    .projection_attempts = native.projection_attempts,
                    .committed_rows = native.committed_rows,
                    .state = native.state,
                    .owns_projection_plan = native.owns_projection_plan == 1,
                };
            }

            pub fn accounting() Accounting {
                const native = c.simd_json_test_stream_accounting_snapshot();
                return .{
                    .live_cursors = native.live_cursors,
                    .live_frames = native.live_frames,
                    .live_key_bytes = native.live_key_bytes,
                    .live_owned_plans = native.live_owned_plans,
                };
            }

            pub fn injectFailure(successful_checkpoints: u64, kind: i32) void {
                c.simd_json_test_stream_inject_failure(successful_checkpoints, kind);
            }

            pub fn clearFailure() void {
                c.simd_json_test_stream_clear_failure();
            }

            pub fn setState(cursor: *OwnedCursor, state: u32) bool {
                const handle = cursor.handle orelse return false;
                return c.simd_json_test_stream_state_set(handle, state) == 1;
            }
        } else struct {};

        comptime {
            if (c.SIMD_JSON_ABI_VERSION != 3)
                @compileError("stream cursor ownership requires private ABI version 3");
            if (c.SIMD_JSON_ARRAY_INDEX_UNAVAILABLE != std.math.maxInt(u64) or
                c.SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE != std.math.maxInt(u32))
                @compileError("ABI v3 stream sentinels changed");
            if (c.SIMD_JSON_STREAM_MAX_BATCH_SIZE != 10000 or
                c.SIMD_JSON_STREAM_MAX_BATCH_BYTES != 67108864)
                @compileError("ABI v3 stream limits changed");

            if (@sizeOf(c.simd_json_stream_target) != 32 or
                @offsetOf(c.simd_json_stream_target, "segments") != 0 or
                @offsetOf(c.simd_json_stream_target, "segment_count") != 8 or
                @offsetOf(c.simd_json_stream_target, "key_bytes") != 16 or
                @offsetOf(c.simd_json_stream_target, "key_bytes_length") != 24)
                @compileError("stream target layout changed");
            if (@sizeOf(c.simd_json_stream_cursor_config) != 40 or
                @offsetOf(c.simd_json_stream_cursor_config, "projection_plan") != 0 or
                @offsetOf(c.simd_json_stream_cursor_config, "row_limit") != 8 or
                @offsetOf(c.simd_json_stream_cursor_config, "encoded_byte_limit") != 16 or
                @offsetOf(c.simd_json_stream_cursor_config, "parent_generation") != 24 or
                @offsetOf(c.simd_json_stream_cursor_config, "reserved") != 32)
                @compileError("stream cursor config layout changed");
            if (@sizeOf(c.simd_json_cancellation_probe) != 16)
                @compileError("stream cancellation layout changed");
            if (@sizeOf(c.simd_json_stream_row) != 32 or
                @offsetOf(c.simd_json_stream_row, "array_index") != 0 or
                @offsetOf(c.simd_json_stream_row, "slot_offset") != 8 or
                @offsetOf(c.simd_json_stream_row, "slot_count") != 16 or
                @offsetOf(c.simd_json_stream_row, "encoded_bytes") != 24)
                @compileError("stream row layout changed");
            if (@sizeOf(c.simd_json_stream_batch_storage) != 80 or
                @offsetOf(c.simd_json_stream_batch_storage, "rows") != 0 or
                @offsetOf(c.simd_json_stream_batch_storage, "row_capacity") != 8 or
                @offsetOf(c.simd_json_stream_batch_storage, "slots") != 16 or
                @offsetOf(c.simd_json_stream_batch_storage, "slot_capacity") != 24 or
                @offsetOf(c.simd_json_stream_batch_storage, "copied_bytes") != 32 or
                @offsetOf(c.simd_json_stream_batch_storage, "copied_byte_capacity") != 40 or
                @offsetOf(c.simd_json_stream_batch_storage, "produced_rows") != 48 or
                @offsetOf(c.simd_json_stream_batch_storage, "produced_slots") != 56 or
                @offsetOf(c.simd_json_stream_batch_storage, "encoded_bytes") != 64 or
                @offsetOf(c.simd_json_stream_batch_storage, "done") != 72 or
                @offsetOf(c.simd_json_stream_batch_storage, "reserved") != 76)
                @compileError("stream batch layout changed");
            if (@sizeOf(c.simd_json_stream_status) != 32 or
                @offsetOf(c.simd_json_stream_status, "code") != 0 or
                @offsetOf(c.simd_json_stream_status, "native_code") != 4 or
                @offsetOf(c.simd_json_stream_status, "byte_offset") != 8 or
                @offsetOf(c.simd_json_stream_status, "output_slot") != 16 or
                @offsetOf(c.simd_json_stream_status, "reserved") != 20 or
                @offsetOf(c.simd_json_stream_status, "array_index") != 24)
                @compileError("stream status layout changed");

            const states = [_]u32{
                c.SIMD_JSON_STREAM_CURSOR_READY,
                c.SIMD_JSON_STREAM_CURSOR_RUNNING,
                c.SIMD_JSON_STREAM_CURSOR_DONE,
                c.SIMD_JSON_STREAM_CURSOR_CANCELLED,
                c.SIMD_JSON_STREAM_CURSOR_CLOSED,
            };
            for (states, 0..) |value, index| {
                if (value != index) @compileError("stream cursor states changed");
            }
            if (!@hasDecl(c, "simd_json_stream_cursor_create") or
                !@hasDecl(c, "simd_json_stream_cursor_destroy") or
                !@hasDecl(c, "simd_json_stream_next_batch"))
                @compileError("stream ABI functions are incomplete");

            _ = Self;
        }
    };
}

// covers: simd_json.stream_cursor.private_abi_v3 simd_json.stream_cursor.opaque_cursor simd_json.stream_cursor.projection_plan_reuse simd_json.stream_cursor.exception_and_failure_cleanup
