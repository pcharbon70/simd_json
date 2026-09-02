const std = @import("std");
const projection_module = @import("projection_plan");
const stream_module = @import("stream_cursor");
const document_module = @import("document_resource");
const c = @cImport({
    @cDefine("SIMD_JSON_TESTING", "1");
    @cInclude("simd_json_abi.h");
    @cInclude("simd_json_test_hooks.h");
});
const projection = projection_module.Implementation(c);
const stream = stream_module.Implementation(c, projection);
const document = document_module.Implementation(c);

// covers: simd_json.stream_cursor.private_abi_v3 simd_json.stream_cursor.opaque_cursor simd_json.stream_cursor.parent_retention simd_json.stream_cursor.projection_plan_reuse simd_json.stream_cursor.exception_and_failure_cleanup simd_json.stream_cursor.abi_v3_conformance
// covers: simd_json.stream_cursor.single_target_lookup simd_json.stream_cursor.forward_only_rows simd_json.stream_cursor.row_count_bound simd_json.stream_cursor.encoded_byte_bound simd_json.stream_cursor.transactional_batch simd_json.stream_cursor.copied_row_values simd_json.stream_cursor.exact_done_detection simd_json.stream_cursor.complete_consumption_validation simd_json.stream_cursor.indexed_status simd_json.stream_cursor.batch_boundary simd_json.stream_cursor.internal_diagnostics simd_json.stream_cursor.target_lookup_and_retention simd_json.stream_cursor.reused_row_projection simd_json.stream_cursor.row_and_byte_boundaries simd_json.stream_cursor.exact_end_and_trailing_validation simd_json.stream_cursor.indexed_row_failure simd_json.stream_cursor.cancellation_and_cleanup_matrix

const NativeDocument = struct {
    storage: []u8,
    parser: ?*c.simd_json_parser,
    handle: ?*c.simd_json_document,

    fn init() !NativeDocument {
        return initSource("{\"rows\":[{\"value\":1}]}");
    }

    fn initSource(source: []const u8) !NativeDocument {
        return initSourceMode(source, false);
    }

    fn initUnvalidated(source: []const u8) !NativeDocument {
        return initSourceMode(source, true);
    }

    fn initSourceMode(source: []const u8, unvalidated: bool) !NativeDocument {
        const capacity = try std.math.add(usize, source.len, @intCast(c.SIMD_JSON_REQUIRED_PADDING));
        const storage = try std.testing.allocator.alloc(u8, capacity);
        errdefer std.testing.allocator.free(storage);
        @memcpy(storage[0..source.len], source);
        @memset(storage[source.len..], 0);
        var parser: ?*c.simd_json_parser = null;
        if (c.simd_json_parser_create(&parser).code != c.SIMD_JSON_STATUS_OK)
            return error.ParserCreate;
        errdefer c.simd_json_parser_destroy(parser);
        var handle: ?*c.simd_json_document = null;
        const status = if (unvalidated)
            c.simd_json_test_document_open_unvalidated(parser, storage.ptr, source.len, capacity, &handle)
        else
            c.simd_json_document_open(parser, storage.ptr, source.len, capacity, &handle);
        if (status.code != c.SIMD_JSON_STATUS_OK)
            return error.DocumentOpen;
        return .{ .storage = storage, .parser = parser, .handle = handle };
    }

    fn deinit(self: *NativeDocument) void {
        c.simd_json_document_destroy(self.handle);
        c.simd_json_parser_destroy(self.parser);
        std.testing.allocator.free(self.storage);
        self.* = undefined;
    }
};

fn makePlan() !projection.OwnedPlan {
    const segments = [_]projection.Segment{.{ .object_key = "value" }};
    const paths = [_]projection.NormalizedPath{.{ .path_slot = 0, .segments = &segments }};
    const entries = [_]projection.NormalizedEntry{.{ .output_slot = 0, .path_slot = 0 }};
    return projection.OwnedPlan.init(std.testing.allocator, .{
        .entries = &entries,
        .paths = &paths,
    });
}

fn makeScalarPlan() !projection.OwnedPlan {
    const signed_segments = [_]projection.Segment{.{ .object_key = "signed" }};
    const unsigned_segments = [_]projection.Segment{.{ .object_key = "unsigned" }};
    const float_segments = [_]projection.Segment{.{ .object_key = "float" }};
    const bool_segments = [_]projection.Segment{.{ .object_key = "bool" }};
    const null_segments = [_]projection.Segment{.{ .object_key = "null" }};
    const string_segments = [_]projection.Segment{.{ .object_key = "string" }};
    const nested_segments = [_]projection.Segment{
        .{ .object_key = "nested" },
        .{ .object_key = "items" },
        .{ .array_index = 1 },
    };
    const paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &signed_segments },
        .{ .path_slot = 1, .segments = &unsigned_segments },
        .{ .path_slot = 2, .segments = &float_segments },
        .{ .path_slot = 3, .segments = &bool_segments },
        .{ .path_slot = 4, .segments = &null_segments },
        .{ .path_slot = 5, .segments = &string_segments },
        .{ .path_slot = 6, .segments = &nested_segments },
    };
    const entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
        .{ .output_slot = 1, .path_slot = 1 },
        .{ .output_slot = 2, .path_slot = 2 },
        .{ .output_slot = 3, .path_slot = 3 },
        .{ .output_slot = 4, .path_slot = 4 },
        .{ .output_slot = 5, .path_slot = 5 },
        .{ .output_slot = 6, .path_slot = 6 },
    };
    return projection.OwnedPlan.init(std.testing.allocator, .{
        .entries = &entries,
        .paths = &paths,
    });
}

fn expectQuiescent() !void {
    try std.testing.expect(stream.testing.accounting().isQuiescent());
    try std.testing.expect(projection.testing.accounting().isQuiescent());
}

test "normalized target and plan transfer produce one opaque cursor" {
    const target_segments = [_]stream.Segment{
        .{ .object_key = "rows" },
        .{ .array_index = std.math.maxInt(u64) },
        .{ .object_key = "雪" },
        .{ .object_key = "" },
    };
    comptime {
        if (@hasField(stream.Target, "owner_pid") or @hasField(stream.Target, "beam_term") or
            @hasField(stream.Target, "resource_pointer"))
            @compileError("BEAM identity must not cross private ABI v3");
    }

    try expectQuiescent();
    var native_document = try NativeDocument.init();
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &target_segments },
        .{ .rows = c.SIMD_JSON_STREAM_MAX_BATCH_SIZE, .encoded_bytes = c.SIMD_JSON_STREAM_MAX_BATCH_BYTES },
        41,
    );
    const summary = stream.testing.summary(&cursor).?;
    try std.testing.expect(!plan.isAlive());
    try std.testing.expectEqual(@as(u64, 4), summary.target_segments);
    try std.testing.expectEqual(@as(u64, 3), summary.object_segments);
    try std.testing.expectEqual(@as(u64, 1), summary.array_segments);
    try std.testing.expectEqual(@as(u64, 7), summary.key_bytes);
    try std.testing.expectEqual(@as(u64, 41), summary.parent_generation);
    try std.testing.expect(summary.owns_projection_plan);
    cursor.deinit();
    cursor.deinit();
    try expectQuiescent();
}

test "parent accounting remains retained until cursor teardown" {
    try std.testing.expect(document.testing.reset());
    var native_document = try NativeDocument.init();
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    document.testing.retainParent();
    var cursor = stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{} },
        .{ .rows = 1, .encoded_bytes = 1 },
        7,
    ) catch |failure| {
        document.testing.releaseParent();
        return failure;
    };
    try std.testing.expectEqual(@as(usize, 1), document.testing.snapshot().retained_parents);
    cursor.deinit();
    document.testing.releaseParent();
    try std.testing.expectEqual(@as(usize, 0), document.testing.snapshot().retained_parents);
    try expectQuiescent();
}

test "native cursor checkpoints preserve exactly one plan cleanup owner" {
    const kinds = [_]i32{
        c.SIMD_JSON_TEST_FAILURE_SIMDJSON,
        c.SIMD_JSON_TEST_FAILURE_BAD_ALLOC,
        c.SIMD_JSON_TEST_FAILURE_STANDARD,
        c.SIMD_JSON_TEST_FAILURE_UNKNOWN,
    };
    var native_document = try NativeDocument.init();
    defer native_document.deinit();
    for (kinds) |kind| {
        for (0..5) |checkpoint| {
            var plan = try makePlan();
            defer plan.deinit();
            stream.testing.injectFailure(@intCast(checkpoint), kind);
            if (stream.OwnedCursor.init(
                std.testing.allocator,
                native_document.handle,
                &plan,
                .{ .segments = &.{.{ .object_key = "rows" }} },
                .{ .rows = 1, .encoded_bytes = 64 },
                11,
            )) |created| {
                var cursor = created;
                stream.testing.clearFailure();
                try std.testing.expectEqual(@as(usize, 4), checkpoint);
                cursor.deinit();
            } else |failure| {
                stream.testing.clearFailure();
                if (kind == c.SIMD_JSON_TEST_FAILURE_BAD_ALLOC)
                    try std.testing.expectEqual(error.OutOfMemory, failure)
                else
                    try std.testing.expectEqual(error.NativeFailure, failure);
            }
            plan.deinit();
            try expectQuiescent();
        }
    }
}

fn exerciseTargetAllocation(allocator: std.mem.Allocator) !void {
    var native_document = try NativeDocument.init();
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{ .{ .object_key = "rows" }, .{ .array_index = 0 } } },
        .{ .rows = 1, .encoded_bytes = 64 },
        23,
    );
    defer cursor.deinit();
}

test "every Zig target allocation failure releases earlier ownership" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseTargetAllocation,
        .{},
    );
    try expectQuiescent();
}

test "owned batches preserve row order bounds and copied strings" {
    var native_document = try NativeDocument.initSource(
        "{\"rows\":[{\"value\":\"alpha\"},{\"value\":\"beta\"},{\"value\":\"gamma\"}]}",
    );
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{.{ .object_key = "rows" }} },
        .{ .rows = 2, .encoded_bytes = 1024 },
        31,
    );
    defer cursor.deinit();
    var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
    defer batch.deinit();

    try std.testing.expect(batch.next(&cursor) == null);
    try std.testing.expectEqual(@as(usize, 2), batch.produced_rows);
    try std.testing.expectEqual(@as(usize, 2), batch.produced_slots);
    try std.testing.expect(!batch.done);
    try std.testing.expectEqual(@as(u64, 0), batch.rowSlice()[0].array_index);
    try std.testing.expectEqual(@as(u64, 1), batch.rowSlice()[1].array_index);
    const first = batch.slotSlice()[0].value.string;
    const second = batch.slotSlice()[1].value.string;
    try std.testing.expectEqualStrings("alpha", first.data[0..first.length]);
    try std.testing.expectEqualStrings("beta", second.data[0..second.length]);

    try std.testing.expect(batch.next(&cursor) == null);
    try std.testing.expectEqual(@as(usize, 1), batch.produced_rows);
    try std.testing.expect(batch.done);
    try std.testing.expectEqual(@as(u64, 2), batch.rowSlice()[0].array_index);
    const third = batch.slotSlice()[0].value.string;
    try std.testing.expectEqualStrings("gamma", third.data[0..third.length]);
    const summary = stream.testing.summary(&cursor).?;
    try std.testing.expectEqual(@as(u64, 1), summary.target_lookups);
    try std.testing.expectEqual(@as(u64, 3), summary.projection_attempts);
    try std.testing.expectEqual(@as(u64, 3), summary.committed_rows);
    try std.testing.expectEqual(@as(u64, 2), summary.batch_sequence);
}

test "an oversized row fails atomically with its source index" {
    var native_document = try NativeDocument.initSource(
        "{\"rows\":[{\"value\":\"too-large\"}]}",
    );
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{.{ .object_key = "rows" }} },
        .{ .rows = 1, .encoded_bytes = 64 },
        37,
    );
    defer cursor.deinit();
    var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
    defer batch.deinit();
    const failure = batch.next(&cursor).?;
    try std.testing.expectEqual(stream.FailureCode.batch_too_large, failure.code);
    try std.testing.expectEqual(@as(?u64, 0), failure.array_index);
    try std.testing.expectEqual(@as(usize, 0), batch.produced_rows);
    try std.testing.expectEqual(@as(usize, 0), batch.produced_slots);
    try std.testing.expectEqual(@as(u64, 0), batch.encoded_bytes);
}

test "natural completion rejects malformed content after a nested target" {
    var native_document = try NativeDocument.initUnvalidated(
        "{\"rows\":[{\"value\":1}],\"tail\":[1,]}",
    );
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{.{ .object_key = "rows" }} },
        .{ .rows = 2, .encoded_bytes = 1024 },
        43,
    );
    defer cursor.deinit();
    var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
    defer batch.deinit();
    const failure = batch.next(&cursor).?;
    try std.testing.expectEqual(stream.FailureCode.invalid_json, failure.code);
    try std.testing.expectEqual(@as(usize, 0), batch.produced_rows);
    try std.testing.expect(!batch.done);
}

test "byte-limited batches retain the next projected row without replay" {
    var native_document = try NativeDocument.initSource(
        "{\"rows\":[{\"value\":\"first\"},{\"value\":\"second\"}]}",
    );
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{.{ .object_key = "rows" }} },
        .{ .rows = 2, .encoded_bytes = 64 },
        47,
    );
    defer cursor.deinit();
    var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
    defer batch.deinit();

    try std.testing.expect(batch.next(&cursor) == null);
    try std.testing.expectEqual(@as(usize, 1), batch.produced_rows);
    try std.testing.expect(!batch.done);
    try std.testing.expect(batch.next(&cursor) == null);
    try std.testing.expectEqual(@as(usize, 1), batch.produced_rows);
    try std.testing.expect(batch.done);
    const summary = stream.testing.summary(&cursor).?;
    try std.testing.expectEqual(@as(u64, 1), summary.target_lookups);
    try std.testing.expectEqual(@as(u64, 2), summary.projection_attempts);
    try std.testing.expectEqual(@as(u64, 2), summary.committed_rows);
}

test "injected next-batch exceptions discard all visible rows" {
    const kinds = [_]i32{
        c.SIMD_JSON_TEST_FAILURE_SIMDJSON,
        c.SIMD_JSON_TEST_FAILURE_BAD_ALLOC,
        c.SIMD_JSON_TEST_FAILURE_STANDARD,
        c.SIMD_JSON_TEST_FAILURE_UNKNOWN,
    };
    for (kinds) |kind| {
        for (0..4) |checkpoint| {
            var native_document = try NativeDocument.init();
            defer native_document.deinit();
            var plan = try makePlan();
            defer plan.deinit();
            var cursor = try stream.OwnedCursor.init(
                std.testing.allocator,
                native_document.handle,
                &plan,
                .{ .segments = &.{.{ .object_key = "rows" }} },
                .{ .rows = 2, .encoded_bytes = 1024 },
                53,
            );
            defer cursor.deinit();
            var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
            defer batch.deinit();
            stream.testing.injectFailure(checkpoint, kind);
            const failure = batch.next(&cursor).?;
            stream.testing.clearFailure();
            if (kind == c.SIMD_JSON_TEST_FAILURE_BAD_ALLOC)
                try std.testing.expectEqual(stream.FailureCode.out_of_memory, failure.code)
            else if (kind == c.SIMD_JSON_TEST_FAILURE_SIMDJSON)
                try std.testing.expectEqual(stream.FailureCode.invalid_json, failure.code)
            else
                try std.testing.expectEqual(stream.FailureCode.internal_failure, failure.code);
            try std.testing.expectEqual(@as(usize, 0), batch.produced_rows);
            try std.testing.expectEqual(@as(usize, 0), batch.produced_slots);
            try std.testing.expectEqual(@as(u64, 0), batch.encoded_bytes);
            try std.testing.expect(!batch.done);
        }
    }
    stream.testing.clearFailure();
}

test "one row preserves every scalar tag and mixed nested path" {
    var native_document = try NativeDocument.initSource(
        "{\"rows\":[{\"signed\":-7,\"unsigned\":18446744073709551615,\"float\":1.25,\"bool\":true,\"null\":null,\"string\":\"a\\u0000雪\",\"nested\":{\"items\":[0,42]}}]}",
    );
    defer native_document.deinit();
    var plan = try makeScalarPlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{.{ .object_key = "rows" }} },
        .{ .rows = 1, .encoded_bytes = 4096 },
        59,
    );
    defer cursor.deinit();
    var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
    defer batch.deinit();
    try std.testing.expect(batch.next(&cursor) == null);
    try std.testing.expect(batch.done);
    const slots = batch.slotSlice();
    try std.testing.expectEqual(@as(usize, 7), slots.len);
    try std.testing.expectEqual(@as(u32, c.SIMD_JSON_RESULT_SIGNED_INTEGER), slots[0].tag);
    try std.testing.expectEqual(@as(i64, -7), slots[0].value.signed_integer);
    try std.testing.expectEqual(@as(u32, c.SIMD_JSON_RESULT_UNSIGNED_INTEGER), slots[1].tag);
    try std.testing.expectEqual(std.math.maxInt(u64), slots[1].value.unsigned_integer);
    try std.testing.expectEqual(@as(u32, c.SIMD_JSON_RESULT_DOUBLE), slots[2].tag);
    try std.testing.expectEqual(@as(f64, 1.25), slots[2].value.floating_point);
    try std.testing.expectEqual(@as(u32, c.SIMD_JSON_RESULT_BOOLEAN), slots[3].tag);
    try std.testing.expectEqual(@as(u64, 1), slots[3].value.boolean);
    try std.testing.expectEqual(@as(u32, c.SIMD_JSON_RESULT_NULL), slots[4].tag);
    try std.testing.expectEqual(@as(u32, c.SIMD_JSON_RESULT_STRING), slots[5].tag);
    const string = slots[5].value.string;
    try std.testing.expectEqualStrings("a\x00雪", string.data[0..string.length]);
    try std.testing.expectEqual(@as(i64, 42), slots[6].value.signed_integer);
}

test "an empty root array completes without an extra probe" {
    var native_document = try NativeDocument.initSource("[]");
    defer native_document.deinit();
    var plan = try makePlan();
    defer plan.deinit();
    var cursor = try stream.OwnedCursor.init(
        std.testing.allocator,
        native_document.handle,
        &plan,
        .{ .segments = &.{} },
        .{ .rows = 1, .encoded_bytes = 256 },
        61,
    );
    defer cursor.deinit();
    var batch = try stream.OwnedBatch.init(std.testing.allocator, &cursor);
    defer batch.deinit();
    try std.testing.expect(batch.next(&cursor) == null);
    try std.testing.expectEqual(@as(usize, 0), batch.produced_rows);
    try std.testing.expect(batch.done);
    const summary = stream.testing.summary(&cursor).?;
    try std.testing.expectEqual(@as(u64, 1), summary.target_lookups);
    try std.testing.expectEqual(@as(u64, 1), summary.batch_sequence);
}
