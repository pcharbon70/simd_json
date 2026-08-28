const std = @import("std");
const resource_module = @import("document_resource");
const c = @cImport({
    @cInclude("simd_json_abi.h");
});
const resource = resource_module.Implementation(c);

test "canonical C status values adapt to a closed Zig status" {
    const success = resource.adaptStatus(.{
        .code = c.SIMD_JSON_STATUS_OK,
        .native_code = c.SIMD_JSON_NATIVE_CODE_UNAVAILABLE,
        .byte_offset = c.SIMD_JSON_BYTE_OFFSET_UNAVAILABLE,
    });
    try std.testing.expect(success == .ok);

    const unknown = resource.adaptStatus(.{
        .code = std.math.maxInt(i32),
        .native_code = 99,
        .byte_offset = 7,
    });
    try std.testing.expect(unknown == .internal_failure);
    try std.testing.expectEqual(@as(?i32, 99), unknown.internal_failure.native_code);
    try std.testing.expectEqual(@as(?u64, 7), unknown.internal_failure.byte_offset);
}

test "empty document state is closed and safely destructible" {
    var state = resource.DocumentState.empty();
    try std.testing.expectEqual(resource.Lifecycle.closed, state.lifecycleState());
    try std.testing.expect(!state.hasOwnedNativeState());
    try std.testing.expectEqual(@as(usize, 0), state.logical_length);
    try std.testing.expectEqual(@as(u64, 0), state.generation.load(.acquire));
    try std.testing.expectEqual(@as(usize, 0), state.admitted_operations.load(.acquire));
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership
