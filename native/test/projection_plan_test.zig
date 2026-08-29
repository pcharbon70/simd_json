const std = @import("std");
const projection_module = @import("projection_plan");
const c = @cImport({
    @cDefine("SIMD_JSON_TESTING", "1");
    @cInclude("simd_json_abi.h");
    @cInclude("simd_json_test_hooks.h");
});
const projection = projection_module.Implementation(c);

fn expectQuiescent() !void {
    try std.testing.expect(projection.testing.accounting().isQuiescent());
}

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

// covers: simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.abi_v2_conformance
