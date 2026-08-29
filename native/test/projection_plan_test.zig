const std = @import("std");
const projection_module = @import("projection_plan");
const c = @cImport({
    @cDefine("SIMD_JSON_TESTING", "1");
    @cInclude("simd_json_abi.h");
    @cInclude("simd_json_nif_internal.h");
    @cInclude("simd_json_test_hooks.h");
});
const projection = projection_module.Implementation(c);

fn expectQuiescent() !void {
    try std.testing.expect(projection.testing.accounting().isQuiescent());
}

const NativeDocument = struct {
    storage: []u8,
    parser: ?*c.simd_json_parser,
    document: ?*c.simd_json_document,

    fn init(source: []const u8) !NativeDocument {
        const capacity = try std.math.add(
            usize,
            source.len,
            @intCast(c.SIMD_JSON_REQUIRED_PADDING),
        );
        const storage = try std.testing.allocator.alloc(u8, capacity);
        errdefer std.testing.allocator.free(storage);
        @memcpy(storage[0..source.len], source);
        @memset(storage[source.len..], 0);

        var parser: ?*c.simd_json_parser = null;
        const parser_status = c.simd_json_parser_create(&parser);
        if (parser_status.code != c.SIMD_JSON_STATUS_OK or parser == null)
            return error.NativeParserCreate;
        errdefer c.simd_json_parser_destroy(parser);

        var document: ?*c.simd_json_document = null;
        const document_status = c.simd_json_document_open(
            parser,
            storage.ptr,
            @intCast(source.len),
            @intCast(capacity),
            &document,
        );
        if (document_status.code != c.SIMD_JSON_STATUS_OK or document == null)
            return error.NativeDocumentOpen;

        return .{
            .storage = storage,
            .parser = parser,
            .document = document,
        };
    }

    fn deinit(self: *NativeDocument) void {
        c.simd_json_document_destroy(self.document);
        c.simd_json_parser_destroy(self.parser);
        std.testing.allocator.free(self.storage);
        self.* = undefined;
    }
};

test "real Phase 1 normalized fixture round-trips without output keys" {
    const shared = [_]projection.Segment{
        .{ .object_key = "customer" },
        .{ .object_key = "id" },
    };
    const unicode = [_]projection.Segment{
        .{ .object_key = "" },
        .{ .object_key = "café" },
        .{ .array_index = 0 },
        .{ .array_index = std.math.maxInt(u64) },
    };
    const ready = [_]projection.Segment{.{ .object_key = "ready" }};
    const left = [_]projection.Segment{
        .{ .object_key = "root" },
        .{ .object_key = "left" },
    };
    const right = [_]projection.Segment{
        .{ .object_key = "root" },
        .{ .object_key = "right" },
    };
    const paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &shared },
        .{ .path_slot = 1, .segments = &unicode },
        .{ .path_slot = 2, .segments = &ready },
        .{ .path_slot = 3, .segments = &left },
        .{ .path_slot = 4, .segments = &right },
    };
    const entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
        .{ .output_slot = 1, .path_slot = 0 },
        .{ .output_slot = 2, .path_slot = 1 },
        .{ .output_slot = 3, .path_slot = 2 },
        .{ .output_slot = 4, .path_slot = 3 },
        .{ .output_slot = 5, .path_slot = 4 },
        .{ .output_slot = 6, .path_slot = 2 },
    };
    const reordered_entries = [_]projection.NormalizedEntry{
        entries[6], entries[2], entries[4], entries[0], entries[5], entries[1], entries[3],
    };

    comptime {
        if (@hasField(projection.NormalizedEntry, "output_key"))
            @compileError("caller output keys must not cross the C ABI");
        if (@hasField(projection.NormalizedProjection, "beam_term"))
            @compileError("raw BEAM terms must not cross the C ABI");
    }

    try expectQuiescent();
    var first = try projection.OwnedPlan.init(std.testing.allocator, .{
        .entries = &entries,
        .paths = &paths,
    });
    const first_summary = projection.testing.summary(&first).?;
    try std.testing.expectEqual(@as(u64, 7), first_summary.output_slots);
    try std.testing.expectEqual(@as(u64, 11), first_summary.nodes);
    try std.testing.expectEqual(@as(u64, 8), first_summary.object_edges);
    try std.testing.expectEqual(@as(u64, 2), first_summary.array_edges);
    try std.testing.expectEqual(@as(u64, 7), first_summary.terminals);
    try std.testing.expectEqual(@as(u64, 33), first_summary.key_bytes);
    try std.testing.expectEqual(@as(u64, 4), first_summary.maximum_depth);

    var second = try projection.OwnedPlan.init(std.testing.allocator, .{
        .entries = &reordered_entries,
        .paths = &paths,
    });
    const second_summary = projection.testing.summary(&second).?;
    try std.testing.expectEqualDeep(first_summary, second_summary);

    second.deinit();
    second.deinit();
    first.deinit();
    first.deinit();
    try expectQuiescent();
}

test "serialization rejects inconsistent normalized structures before native allocation" {
    const key_path = [_]projection.Segment{.{ .object_key = "valid" }};
    const other_path = [_]projection.Segment{.{ .array_index = 0 }};
    const invalid_utf8 = [_]projection.Segment{.{ .object_key = "\xff" }};
    const valid_paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &key_path },
    };
    const two_paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &key_path },
        .{ .path_slot = 1, .segments = &other_path },
    };
    const valid_entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
    };
    const duplicate_entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
        .{ .output_slot = 0, .path_slot = 0 },
    };
    const missing_path_entry = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 9 },
    };
    const invalid_paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &invalid_utf8 },
    };
    const noncanonical_paths = [_]projection.NormalizedPath{
        .{ .path_slot = 1, .segments = &key_path },
    };
    const noncanonical_entry = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 1 },
    };

    try std.testing.expectError(error.InvalidProjection, projection.OwnedPlan.init(
        std.testing.allocator,
        .{ .entries = &.{}, .paths = &.{} },
    ));
    try std.testing.expectError(error.InvalidProjection, projection.OwnedPlan.init(
        std.testing.allocator,
        .{ .entries = &duplicate_entries, .paths = &valid_paths },
    ));
    try std.testing.expectError(error.InvalidProjection, projection.OwnedPlan.init(
        std.testing.allocator,
        .{ .entries = &missing_path_entry, .paths = &valid_paths },
    ));
    try std.testing.expectError(error.InvalidProjection, projection.OwnedPlan.init(
        std.testing.allocator,
        .{ .entries = &valid_entries, .paths = &two_paths },
    ));
    try std.testing.expectError(error.InvalidProjection, projection.OwnedPlan.init(
        std.testing.allocator,
        .{ .entries = &valid_entries, .paths = &invalid_paths },
    ));
    try std.testing.expectError(error.InvalidProjection, projection.OwnedPlan.init(
        std.testing.allocator,
        .{ .entries = &noncanonical_entry, .paths = &noncanonical_paths },
    ));
    try expectQuiescent();
}

fn exerciseSerializationAllocation(allocator: std.mem.Allocator) !void {
    const first = [_]projection.Segment{
        .{ .object_key = "root" },
        .{ .object_key = "first" },
    };
    const second = [_]projection.Segment{
        .{ .object_key = "root" },
        .{ .array_index = 17 },
    };
    const paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &first },
        .{ .path_slot = 1, .segments = &second },
    };
    const entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
        .{ .output_slot = 1, .path_slot = 1 },
    };

    var plan = try projection.OwnedPlan.init(allocator, .{
        .entries = &entries,
        .paths = &paths,
    });
    defer plan.deinit();
    try std.testing.expect(plan.isAlive());
}

test "every Zig descriptor and arena allocation failure releases earlier ownership" {
    try expectQuiescent();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseSerializationAllocation,
        .{},
    );
    try expectQuiescent();
}

test "every native construction checkpoint returns through owned Zig cleanup" {
    const segments = [_]projection.Segment{
        .{ .object_key = "root" },
        .{ .object_key = "left" },
        .{ .object_key = "root" },
        .{ .object_key = "right" },
    };
    const first_path = [_]projection.Segment{ segments[0], segments[1] };
    const second_path = [_]projection.Segment{ segments[2], segments[3] };
    const paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &first_path },
        .{ .path_slot = 1, .segments = &second_path },
    };
    const entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
        .{ .output_slot = 1, .path_slot = 1 },
        .{ .output_slot = 2, .path_slot = 0 },
    };

    var observed_success = false;
    for (0..256) |checkpoint| {
        projection.testing.injectFailure(
            @intCast(checkpoint),
            c.SIMD_JSON_TEST_FAILURE_BAD_ALLOC,
        );

        if (projection.OwnedPlan.init(std.testing.allocator, .{
            .entries = &entries,
            .paths = &paths,
        })) |created| {
            var plan = created;
            projection.testing.clearFailure();
            plan.deinit();
            observed_success = true;
            try std.testing.expect(checkpoint >= 10);
            try expectQuiescent();
            break;
        } else |failure| {
            try std.testing.expectEqual(error.OutOfMemory, failure);
            try expectQuiescent();
        }
    }

    projection.testing.clearFailure();
    try std.testing.expect(observed_success);
    try expectQuiescent();
}

test "one Zig execution returns exact typed slots and preserves borrowed bytes" {
    const string_path = [_]projection.Segment{
        .{ .object_key = "values" },
        .{ .array_index = 4 },
    };
    const signed_path = [_]projection.Segment{
        .{ .object_key = "values" },
        .{ .array_index = 0 },
    };
    const unsigned_path = [_]projection.Segment{
        .{ .object_key = "values" },
        .{ .array_index = 1 },
    };
    const double_path = [_]projection.Segment{
        .{ .object_key = "values" },
        .{ .array_index = 2 },
    };
    const null_path = [_]projection.Segment{
        .{ .object_key = "values" },
        .{ .array_index = 3 },
    };
    const paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &string_path },
        .{ .path_slot = 1, .segments = &signed_path },
        .{ .path_slot = 2, .segments = &unsigned_path },
        .{ .path_slot = 3, .segments = &double_path },
        .{ .path_slot = 4, .segments = &null_path },
    };
    const entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
        .{ .output_slot = 1, .path_slot = 1 },
        .{ .output_slot = 2, .path_slot = 2 },
        .{ .output_slot = 3, .path_slot = 3 },
        .{ .output_slot = 4, .path_slot = 4 },
        .{ .output_slot = 5, .path_slot = 0 },
    };

    var plan = try projection.OwnedPlan.init(std.testing.allocator, .{
        .entries = &entries,
        .paths = &paths,
    });
    defer plan.deinit();
    var document = try NativeDocument.init(
        "{\"unused\":{\"tree\":[1,2]},\"values\":[-7," ++
            "18446744073709551615,1.5,null,\"snow \\u2603\"]}",
    );
    defer document.deinit();

    var results = switch (plan.execute(
        std.testing.allocator,
        document.document,
    )) {
        .success => |owned| owned,
        .failure => |failure| {
            std.debug.print("unexpected projection failure: {any}\n", .{failure});
            return error.UnexpectedProjectionFailure;
        },
    };
    defer results.deinit();

    try std.testing.expectEqualStrings("snow ☃", results.scalar(0).?.string);
    try std.testing.expectEqual(@as(i64, -7), results.scalar(1).?.signed_integer);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        results.scalar(2).?.unsigned_integer,
    );
    try std.testing.expectEqual(@as(f64, 1.5), results.scalar(3).?.floating_point);
    try std.testing.expect(results.scalar(4).? == .null);
    try std.testing.expectEqualStrings("snow ☃", results.scalar(5).?.string);

    const summary = projection.testing.executionSummary(&plan).?;
    try std.testing.expectEqual(@as(u64, 1), summary.execution_entries);
    try std.testing.expectEqual(@as(u64, 7), summary.visited_nodes);
    try std.testing.expectEqual(@as(u64, 3), summary.shared_prefix_visits);
    try std.testing.expectEqual(@as(u64, 6), summary.filled_slots);
}

const CancelContext = struct {
    remaining: usize,
};

fn cancellationProbe(context_pointer: ?*anyopaque) callconv(.c) u32 {
    const context: *CancelContext = @ptrCast(@alignCast(context_pointer.?));
    if (context.remaining == 0) return 1;
    context.remaining -= 1;
    return 0;
}

test "Zig execution adapts failures and cancellation without retaining slots" {
    const selected = [_]projection.Segment{.{ .object_key = "selected" }};
    const paths = [_]projection.NormalizedPath{
        .{ .path_slot = 0, .segments = &selected },
    };
    const entries = [_]projection.NormalizedEntry{
        .{ .output_slot = 0, .path_slot = 0 },
    };

    var plan = try projection.OwnedPlan.init(std.testing.allocator, .{
        .entries = &entries,
        .paths = &paths,
    });
    defer plan.deinit();

    {
        var document = try NativeDocument.init(
            "{\"unselected\":[1,2,3],\"selected\":\"value\"}",
        );
        defer document.deinit();

        var tiny_storage: [1]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&tiny_storage);
        const allocation_failure = plan.execute(fixed.allocator(), document.document);
        try std.testing.expectEqual(
            projection.FailureCode.out_of_memory,
            allocation_failure.failure.code,
        );

        var context = CancelContext{ .remaining = 0 };
        c.simd_json_nif_projection_set_cancellation(
            document.document,
            &context,
            cancellationProbe,
        );
        const cancelled = plan.execute(std.testing.allocator, document.document);
        try std.testing.expectEqual(
            projection.FailureCode.cancelled,
            cancelled.failure.code,
        );
        try std.testing.expectEqual(@as(?u32, null), cancelled.failure.output_slot);

        c.simd_json_nif_projection_clear_cancellation(document.document);
        var results = switch (plan.execute(
            std.testing.allocator,
            document.document,
        )) {
            .success => |owned| owned,
            .failure => return error.UnexpectedProjectionFailure,
        };
        defer results.deinit();
        try std.testing.expectEqualStrings("value", results.scalar(0).?.string);
    }

    {
        var document = try NativeDocument.init("{\"other\":1}");
        defer document.deinit();

        const missing = plan.execute(std.testing.allocator, document.document);
        try std.testing.expectEqual(
            projection.FailureCode.missing_field,
            missing.failure.code,
        );
        try std.testing.expectEqual(@as(?u32, 0), missing.failure.output_slot);

        const consumed = plan.execute(std.testing.allocator, document.document);
        try std.testing.expectEqual(
            projection.FailureCode.cursor_consumed,
            consumed.failure.code,
        );
    }
}

// covers: simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.single_guided_traversal simd_json.projection_engine.scalar_only_materialization simd_json.projection_engine.typed_result_slots simd_json.projection_engine.transactional_conversion simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.object_array_walk simd_json.projection_engine.abi_v2_conformance
