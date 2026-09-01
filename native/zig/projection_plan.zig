const std = @import("std");

/// Operation-owned serialization and lifetime layer for the preserved
/// projection portion of private ABI v3.
/// Caller output keys deliberately do not appear in these types: Phase 1 keeps
/// those BEAM values above this boundary and supplies only numeric slot ids.
pub fn Implementation(comptime c: type) type {
    return struct {
        const Self = @This();
        const test_build = @hasDecl(c, "simd_json_test_projection_summary_read") and
            @hasDecl(c, "simd_json_test_projection_accounting_snapshot");

        pub const Segment = union(enum) {
            object_key: []const u8,
            array_index: u64,
        };

        pub const NormalizedPath = struct {
            path_slot: u64,
            segments: []const Segment,
        };

        pub const NormalizedEntry = struct {
            output_slot: u64,
            path_slot: u64,
        };

        pub const NormalizedProjection = struct {
            entries: []const NormalizedEntry,
            paths: []const NormalizedPath,
        };

        pub const BuildError = error{
            OutOfMemory,
            InvalidProjection,
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
        };

        pub const Failure = struct {
            code: FailureCode,
            native_code: ?i32,
            byte_offset: ?u64,
            output_slot: ?u32,
        };

        pub const Scalar = union(enum) {
            signed_integer: i64,
            unsigned_integer: u64,
            floating_point: f64,
            boolean: bool,
            null,
            string: []const u8,
        };

        pub const OwnedResults = struct {
            allocator: std.mem.Allocator,
            native_slots: []c.simd_json_result_slot,

            pub fn deinit(self: *OwnedResults) void {
                @memset(std.mem.sliceAsBytes(self.native_slots), 0);
                self.allocator.free(self.native_slots);
                self.* = undefined;
            }

            pub fn scalar(self: *const OwnedResults, index: usize) ?Scalar {
                if (index >= self.native_slots.len) return null;
                const slot = self.native_slots[index];
                if (slot.reserved != 0) return null;

                return switch (slot.tag) {
                    c.SIMD_JSON_RESULT_SIGNED_INTEGER => .{ .signed_integer = slot.value.signed_integer },
                    c.SIMD_JSON_RESULT_UNSIGNED_INTEGER => .{ .unsigned_integer = slot.value.unsigned_integer },
                    c.SIMD_JSON_RESULT_DOUBLE => .{ .floating_point = slot.value.floating_point },
                    c.SIMD_JSON_RESULT_BOOLEAN => switch (slot.value.boolean) {
                        0 => .{ .boolean = false },
                        1 => .{ .boolean = true },
                        else => null,
                    },
                    c.SIMD_JSON_RESULT_NULL => .null,
                    c.SIMD_JSON_RESULT_STRING => stringScalar(slot),
                    else => null,
                };
            }

            fn stringScalar(slot: c.simd_json_result_slot) ?Scalar {
                const length = std.math.cast(usize, slot.value.string.length) orelse
                    return null;
                if (length == 0) return .{ .string = "" };
                const data = slot.value.string.data;
                if (data == null) return null;
                return .{ .string = data[0..length] };
            }
        };

        pub const ExecuteOutcome = union(enum) {
            success: OwnedResults,
            failure: Failure,
        };

        const SerializedProjection = struct {
            allocator: std.mem.Allocator,
            entries: []c.simd_json_projection_entry,
            segments: []c.simd_json_projection_segment,
            key_bytes: []u8,

            fn init(
                allocator: std.mem.Allocator,
                normalized: NormalizedProjection,
            ) BuildError!SerializedProjection {
                try validateShape(normalized);

                var segment_count: usize = 0;
                var key_byte_count: usize = 0;
                for (normalized.paths) |path| {
                    segment_count = std.math.add(
                        usize,
                        segment_count,
                        path.segments.len,
                    ) catch return error.InvalidProjection;

                    for (path.segments) |segment| switch (segment) {
                        .object_key => |key| {
                            if (!std.unicode.utf8ValidateSlice(key))
                                return error.InvalidProjection;
                            key_byte_count = std.math.add(
                                usize,
                                key_byte_count,
                                key.len,
                            ) catch return error.InvalidProjection;
                        },
                        .array_index => {},
                    };
                }

                _ = std.math.cast(u64, normalized.entries.len) orelse
                    return error.InvalidProjection;
                if (segment_count > std.math.maxInt(u32))
                    return error.InvalidProjection;
                _ = std.math.cast(u64, segment_count) orelse
                    return error.InvalidProjection;
                _ = std.math.cast(u64, key_byte_count) orelse
                    return error.InvalidProjection;

                const entries = allocator.alloc(
                    c.simd_json_projection_entry,
                    normalized.entries.len,
                ) catch return error.OutOfMemory;
                errdefer allocator.free(entries);

                const segments = allocator.alloc(
                    c.simd_json_projection_segment,
                    segment_count,
                ) catch return error.OutOfMemory;
                errdefer allocator.free(segments);

                const key_bytes = allocator.alloc(u8, key_byte_count) catch
                    return error.OutOfMemory;
                errdefer allocator.free(key_bytes);

                var segment_cursor: usize = 0;
                var key_cursor: usize = 0;
                for (normalized.paths) |path| {
                    for (path.segments) |segment| {
                        switch (segment) {
                            .object_key => |key| {
                                const key_offset = std.math.cast(u64, key_cursor) orelse
                                    return error.InvalidProjection;
                                const key_length = std.math.cast(u64, key.len) orelse
                                    return error.InvalidProjection;
                                @memcpy(key_bytes[key_cursor..][0..key.len], key);
                                key_cursor += key.len;
                                segments[segment_cursor] = .{
                                    .tag = c.SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY,
                                    .reserved = 0,
                                    .key_offset = key_offset,
                                    .key_length = key_length,
                                    .array_index = 0,
                                };
                            },
                            .array_index => |index| {
                                segments[segment_cursor] = .{
                                    .tag = c.SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX,
                                    .reserved = 0,
                                    .key_offset = 0,
                                    .key_length = 0,
                                    .array_index = index,
                                };
                            },
                        }
                        segment_cursor += 1;
                    }
                }

                for (normalized.entries, entries) |entry, *serialized| {
                    const path = findPath(normalized.paths, entry.path_slot) orelse
                        return error.InvalidProjection;
                    const segment_offset = pathOffset(normalized.paths, entry.path_slot) orelse
                        return error.InvalidProjection;
                    serialized.* = .{
                        .output_slot = std.math.cast(u32, entry.output_slot) orelse
                            return error.InvalidProjection,
                        .reserved = 0,
                        .segment_offset = std.math.cast(u64, segment_offset) orelse
                            return error.InvalidProjection,
                        .segment_count = std.math.cast(u64, path.segments.len) orelse
                            return error.InvalidProjection,
                    };
                }

                std.debug.assert(segment_cursor == segment_count);
                std.debug.assert(key_cursor == key_byte_count);
                return .{
                    .allocator = allocator,
                    .entries = entries,
                    .segments = segments,
                    .key_bytes = key_bytes,
                };
            }

            fn deinit(self: *SerializedProjection) void {
                self.allocator.free(self.key_bytes);
                self.allocator.free(self.segments);
                self.allocator.free(self.entries);
                self.* = undefined;
            }
        };

        pub const OwnedPlan = struct {
            handle: ?*c.simd_json_projection_plan = null,
            output_slots: usize = 0,

            pub fn init(
                allocator: std.mem.Allocator,
                normalized: NormalizedProjection,
            ) BuildError!OwnedPlan {
                var serialized = try SerializedProjection.init(allocator, normalized);
                defer serialized.deinit();

                var handle: ?*c.simd_json_projection_plan = null;
                const status = c.simd_json_projection_plan_create(
                    serialized.entries.ptr,
                    @intCast(serialized.entries.len),
                    serialized.segments.ptr,
                    @intCast(serialized.segments.len),
                    serialized.key_bytes.ptr,
                    @intCast(serialized.key_bytes.len),
                    &handle,
                );

                if (status.code != c.SIMD_JSON_STATUS_OK or handle == null) {
                    if (handle) |unexpected| c.simd_json_projection_plan_destroy(unexpected);
                    return switch (status.code) {
                        c.SIMD_JSON_STATUS_OUT_OF_MEMORY => error.OutOfMemory,
                        c.SIMD_JSON_STATUS_INVALID_ARGUMENT => error.InvalidProjection,
                        else => error.NativeFailure,
                    };
                }

                return .{
                    .handle = handle,
                    .output_slots = normalized.entries.len,
                };
            }

            pub fn deinit(self: *OwnedPlan) void {
                const handle = self.handle orelse return;
                self.handle = null;
                self.output_slots = 0;
                c.simd_json_projection_plan_destroy(handle);
            }

            pub fn isAlive(self: *const OwnedPlan) bool {
                return self.handle != null;
            }

            /// Executes the whole immutable plan through one ABI call. The
            /// returned string slices borrow the retained document and must be
            /// copied by the Phase 4 term-conversion owner before cleanup.
            pub fn execute(
                self: *const OwnedPlan,
                allocator: std.mem.Allocator,
                document: ?*c.simd_json_document,
            ) ExecuteOutcome {
                const handle = self.handle orelse return .{
                    .failure = failureWithoutDiagnostics(.invalid_argument),
                };
                const slots = allocator.alloc(
                    c.simd_json_result_slot,
                    self.output_slots,
                ) catch return .{
                    .failure = failureWithoutDiagnostics(.out_of_memory),
                };
                @memset(std.mem.sliceAsBytes(slots), 0);

                const status = c.simd_json_projection_execute(
                    document,
                    handle,
                    slots.ptr,
                    @intCast(slots.len),
                );
                if (status.code != c.SIMD_JSON_STATUS_OK) {
                    @memset(std.mem.sliceAsBytes(slots), 0);
                    allocator.free(slots);
                    return .{ .failure = adaptFailure(status) };
                }

                return .{ .success = .{
                    .allocator = allocator,
                    .native_slots = slots,
                } };
            }
        };

        fn failureWithoutDiagnostics(code: FailureCode) Failure {
            return .{
                .code = code,
                .native_code = null,
                .byte_offset = null,
                .output_slot = null,
            };
        }

        fn adaptFailure(status: c.simd_json_projection_status) Failure {
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
            };
        }

        fn validateShape(normalized: NormalizedProjection) BuildError!void {
            if (normalized.entries.len == 0 or normalized.paths.len == 0 or
                normalized.entries.len > std.math.maxInt(u32) or
                normalized.paths.len > std.math.maxInt(u32))
                return error.InvalidProjection;

            for (normalized.paths, 0..) |path, path_index| {
                if (path.segments.len == 0 or path.path_slot >= normalized.paths.len or
                    path.path_slot > std.math.maxInt(u32))
                    return error.InvalidProjection;
                for (normalized.paths[0..path_index]) |previous| {
                    if (previous.path_slot == path.path_slot)
                        return error.InvalidProjection;
                }
            }

            for (normalized.entries, 0..) |entry, entry_index| {
                if (entry.output_slot >= normalized.entries.len or
                    entry.output_slot > std.math.maxInt(u32) or
                    findPath(normalized.paths, entry.path_slot) == null)
                    return error.InvalidProjection;
                for (normalized.entries[0..entry_index]) |previous| {
                    if (previous.output_slot == entry.output_slot)
                        return error.InvalidProjection;
                }
            }

            for (normalized.paths) |path| {
                var referenced = false;
                for (normalized.entries) |entry| {
                    if (entry.path_slot == path.path_slot) {
                        referenced = true;
                        break;
                    }
                }
                if (!referenced) return error.InvalidProjection;
            }
        }

        fn findPath(
            paths: []const NormalizedPath,
            path_slot: u64,
        ) ?*const NormalizedPath {
            for (paths) |*path| {
                if (path.path_slot == path_slot) return path;
            }
            return null;
        }

        fn pathOffset(paths: []const NormalizedPath, path_slot: u64) ?usize {
            var offset: usize = 0;
            for (paths) |path| {
                if (path.path_slot == path_slot) return offset;
                offset = std.math.add(usize, offset, path.segments.len) catch return null;
            }
            return null;
        }

        pub const testing = if (test_build) struct {
            pub const Summary = struct {
                output_slots: u64,
                nodes: u64,
                object_edges: u64,
                array_edges: u64,
                terminals: u64,
                key_bytes: u64,
                maximum_depth: u64,
                topology_hash: u64,
            };

            pub const Accounting = struct {
                live_plans: u64,
                live_nodes: u64,
                live_key_bytes: u64,

                pub fn isQuiescent(self: Accounting) bool {
                    return self.live_plans == 0 and self.live_nodes == 0 and
                        self.live_key_bytes == 0;
                }
            };

            pub const ExecutionSummary = struct {
                compilation_nanoseconds: u64,
                traversal_nanoseconds: u64,
                execution_entries: u64,
                visited_nodes: u64,
                shared_prefix_visits: u64,
                filled_slots: u64,
                object_fields: u64,
                array_elements: u64,
                skipped_values: u64,
                cancellation_checks: u64,
            };

            pub fn summary(plan: *const OwnedPlan) ?Summary {
                const handle = plan.handle orelse return null;
                var native: c.simd_json_test_projection_summary = undefined;
                if (c.simd_json_test_projection_summary_read(handle, &native) == 0)
                    return null;
                return .{
                    .output_slots = native.output_slots,
                    .nodes = native.nodes,
                    .object_edges = native.object_edges,
                    .array_edges = native.array_edges,
                    .terminals = native.terminals,
                    .key_bytes = native.key_bytes,
                    .maximum_depth = native.maximum_depth,
                    .topology_hash = native.topology_hash,
                };
            }

            pub fn accounting() Accounting {
                const native = c.simd_json_test_projection_accounting_snapshot();
                return .{
                    .live_plans = native.live_plans,
                    .live_nodes = native.live_nodes,
                    .live_key_bytes = native.live_key_bytes,
                };
            }

            pub fn executionSummary(plan: *const OwnedPlan) ?ExecutionSummary {
                const handle = plan.handle orelse return null;
                var native: c.simd_json_test_projection_execution_summary = undefined;
                if (c.simd_json_test_projection_execution_summary_read(
                    handle,
                    &native,
                ) == 0) return null;
                return .{
                    .compilation_nanoseconds = native.compilation_nanoseconds,
                    .traversal_nanoseconds = native.traversal_nanoseconds,
                    .execution_entries = native.execution_entries,
                    .visited_nodes = native.visited_nodes,
                    .shared_prefix_visits = native.shared_prefix_visits,
                    .filled_slots = native.filled_slots,
                    .object_fields = native.object_fields,
                    .array_elements = native.array_elements,
                    .skipped_values = native.skipped_values,
                    .cancellation_checks = native.cancellation_checks,
                };
            }

            pub fn injectFailure(successful_checkpoints: u64, kind: i32) void {
                c.simd_json_test_projection_inject_failure(successful_checkpoints, kind);
            }

            pub fn clearFailure() void {
                c.simd_json_test_projection_clear_failure();
            }
        } else struct {};

        comptime {
            if (c.SIMD_JSON_ABI_VERSION != 3)
                @compileError("projection ownership requires private ABI version 3");
            if (c.SIMD_JSON_MAX_DEPTH != 1024)
                @compileError("projection traversal depth bound changed");
            if (c.SIMD_JSON_OUTPUT_SLOT_UNAVAILABLE != std.math.maxInt(u32) or
                c.SIMD_JSON_BYTE_OFFSET_UNAVAILABLE != std.math.maxInt(u64))
                @compileError("ABI v2 sentinels changed");

            if (@sizeOf(c.simd_json_status) != 16)
                @compileError("Milestone 1 status layout changed");
            if (@sizeOf(c.simd_json_projection_status) != 24 or
                @offsetOf(c.simd_json_projection_status, "code") != 0 or
                @offsetOf(c.simd_json_projection_status, "native_code") != 4 or
                @offsetOf(c.simd_json_projection_status, "byte_offset") != 8 or
                @offsetOf(c.simd_json_projection_status, "output_slot") != 16 or
                @offsetOf(c.simd_json_projection_status, "reserved") != 20)
                @compileError("ABI v2 projection status layout changed");

            if (@sizeOf(c.simd_json_projection_entry) != 24 or
                @offsetOf(c.simd_json_projection_entry, "output_slot") != 0 or
                @offsetOf(c.simd_json_projection_entry, "reserved") != 4 or
                @offsetOf(c.simd_json_projection_entry, "segment_offset") != 8 or
                @offsetOf(c.simd_json_projection_entry, "segment_count") != 16)
                @compileError("projection entry layout changed");

            if (@sizeOf(c.simd_json_projection_segment) != 32 or
                @offsetOf(c.simd_json_projection_segment, "tag") != 0 or
                @offsetOf(c.simd_json_projection_segment, "reserved") != 4 or
                @offsetOf(c.simd_json_projection_segment, "key_offset") != 8 or
                @offsetOf(c.simd_json_projection_segment, "key_length") != 16 or
                @offsetOf(c.simd_json_projection_segment, "array_index") != 24)
                @compileError("projection segment layout changed");

            if (@sizeOf(c.simd_json_borrowed_string) != 16 or
                @offsetOf(c.simd_json_borrowed_string, "data") != 0 or
                @offsetOf(c.simd_json_borrowed_string, "length") != 8 or
                @sizeOf(c.simd_json_result_value) != 16 or
                @sizeOf(c.simd_json_result_slot) != 24 or
                @offsetOf(c.simd_json_result_slot, "tag") != 0 or
                @offsetOf(c.simd_json_result_slot, "reserved") != 4 or
                @offsetOf(c.simd_json_result_slot, "value") != 8)
                @compileError("projection result layout changed");

            const segment_tags = [_]u32{
                c.SIMD_JSON_PROJECTION_SEGMENT_OBJECT_KEY,
                c.SIMD_JSON_PROJECTION_SEGMENT_ARRAY_INDEX,
            };
            if (segment_tags[0] != 1 or segment_tags[1] != 2)
                @compileError("projection segment tags changed");

            const result_tags = [_]u32{
                c.SIMD_JSON_RESULT_EMPTY,
                c.SIMD_JSON_RESULT_SIGNED_INTEGER,
                c.SIMD_JSON_RESULT_UNSIGNED_INTEGER,
                c.SIMD_JSON_RESULT_DOUBLE,
                c.SIMD_JSON_RESULT_BOOLEAN,
                c.SIMD_JSON_RESULT_NULL,
                c.SIMD_JSON_RESULT_STRING,
            };
            for (result_tags, 0..) |value, index| {
                if (value != index) @compileError("projection result tags changed");
            }

            const projection_statuses = [_]c.simd_json_status_code{
                c.SIMD_JSON_STATUS_MISSING_FIELD,
                c.SIMD_JSON_STATUS_INDEX_OUT_OF_BOUNDS,
                c.SIMD_JSON_STATUS_INCORRECT_TYPE,
                c.SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE,
                c.SIMD_JSON_STATUS_CURSOR_CONSUMED,
                c.SIMD_JSON_STATUS_CANCELLED,
            };
            for (projection_statuses, 0..) |value, index| {
                if (value != index + 7) @compileError("projection status values changed");
            }

            if (!@hasDecl(c, "simd_json_projection_plan_create") or
                !@hasDecl(c, "simd_json_projection_plan_destroy") or
                !@hasDecl(c, "simd_json_projection_execute"))
                @compileError("projection ABI functions are incomplete");

            _ = Self;
        }
    };
}

// covers: simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.exception_and_failure_cleanup
