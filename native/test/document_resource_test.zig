const std = @import("std");
const resource_module = @import("document_resource");
const c = @cImport({
    @cDefine("SIMD_JSON_TESTING", "1");
    @cInclude("simd_json_abi.h");
    @cInclude("simd_json_test_hooks.h");
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

test "owned padded input is aligned, initialized, and independent of its source" {
    const source_lengths = [_]usize{ 4, 64, 128, 257 };

    for (source_lengths) |source_length| {
        const source = try std.testing.allocator.alloc(u8, source_length);
        defer std.testing.allocator.free(source);
        @memset(source, ' ');
        @memcpy(source[0..4], "null");

        var state = resource.DocumentState.empty();
        try std.testing.expect(state.openOwned(std.testing.allocator, source) == .ok);
        defer state.destroyOwned();

        try std.testing.expect(state.inputIsAligned());
        try std.testing.expect(state.ownedInputMatches(source));
        try std.testing.expect(state.paddingIsInitialized());
        try std.testing.expectEqual(
            source_length + resource.required_padding_bytes,
            state.padded_input.?.len,
        );
        try std.testing.expect(@intFromPtr(state.padded_input.?.ptr) != @intFromPtr(source.ptr));
        try std.testing.expect(state.cDocumentUsesOwnedInputForTest());

        @memset(source, 'x');
        try std.testing.expect(state.revalidateForTest() == .ok);
    }
}

test "zero length and malformed input cross Zig into C without retaining allocations" {
    const inputs = [_][]const u8{ "", "[1," };

    for (inputs) |input| {
        var state = resource.DocumentState.empty();
        const status = state.openOwned(std.testing.allocator, input);
        try std.testing.expect(status == .unexpected_eof);
        if (status.unexpected_eof.byte_offset) |offset| {
            try std.testing.expect(offset <= input.len);
        }
        try std.testing.expect(!state.hasOwnedNativeState());
        try std.testing.expectEqual(resource.Lifecycle.closed, state.lifecycleState());
    }
}

test "capacity checks reject every representational overflow" {
    try std.testing.expectEqual(
        @as(?usize, resource.required_padding_bytes),
        resource.checkedCapacity(0),
    );
    try std.testing.expect(resource.checkedCapacity(std.math.maxInt(u64)) == null);
    try std.testing.expect(resource.checkedCapacity(std.math.maxInt(u128)) == null);
}

test "guard page follows the exact initialized capacity" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;

    const page_size = std.heap.page_size_min;
    const source_lengths = [_]usize{ 0, 64, 128, page_size - resource.required_padding_bytes };

    for (source_lengths) |source_length| {
        const capacity = resource.checkedCapacity(source_length).?;
        const mapping = try std.posix.mmap(
            null,
            page_size * 2,
            .{},
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        defer std.posix.munmap(mapping);

        const accessible: []align(page_size) u8 = @alignCast(mapping[0..page_size]);
        const protection: std.posix.PROT = .{ .READ = true, .WRITE = true };
        try std.testing.expectEqual(
            std.posix.E.SUCCESS,
            std.posix.errno(std.posix.system.mprotect(accessible.ptr, accessible.len, protection)),
        );

        const allocation_region = accessible[page_size - capacity .. page_size];
        var fixed = std.heap.FixedBufferAllocator.init(allocation_region);
        const source = try std.testing.allocator.alloc(u8, source_length);
        defer std.testing.allocator.free(source);
        @memset(source, ' ');
        if (source.len >= 4) @memcpy(source[0..4], "null");

        var state = resource.DocumentState.empty();
        const status = state.openOwned(fixed.allocator(), source);
        if (source_length == 0) {
            try std.testing.expect(status == .unexpected_eof);
        } else {
            try std.testing.expect(status == .ok);
            try std.testing.expectEqual(
                @intFromPtr(mapping.ptr) + page_size,
                @intFromPtr(state.padded_input.?.ptr) + state.padded_input.?.len,
            );
            state.destroyOwned();
        }
    }
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.input_lifetime
