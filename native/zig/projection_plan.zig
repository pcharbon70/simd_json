const std = @import("std");

/// Operation-owned serialization and lifetime layer for private ABI v2.
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

                return .{ .handle = handle };
            }

            pub fn deinit(self: *OwnedPlan) void {
                const handle = self.handle orelse return;
                self.handle = null;
                c.simd_json_projection_plan_destroy(handle);
            }

            pub fn isAlive(self: *const OwnedPlan) bool {
                return self.handle != null;
            }
        };

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

            pub fn injectFailure(successful_checkpoints: u64, kind: i32) void {
                c.simd_json_test_projection_inject_failure(successful_checkpoints, kind);
            }

            pub fn clearFailure() void {
                c.simd_json_test_projection_clear_failure();
            }
        } else struct {};

        comptime {
            if (c.SIMD_JSON_ABI_VERSION != 2)
                @compileError("projection ownership requires private ABI version 2");
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
