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

const NativeDocument = struct {
    storage: []u8,
    parser: ?*c.simd_json_parser,
    handle: ?*c.simd_json_document,

    fn init() !NativeDocument {
        return initSource("{\"rows\":[{\"value\":1}]}");
    }

    fn initSource(source: []const u8) !NativeDocument {
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
        if (c.simd_json_document_open(parser, storage.ptr, source.len, capacity, &handle).code != c.SIMD_JSON_STATUS_OK)
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
