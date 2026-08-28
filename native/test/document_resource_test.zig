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
        try std.testing.expect(state.closeAndDestroy());
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
            try std.testing.expect(state.closeAndDestroy());
        }
    }
}

test "construction failures roll back every completed ownership edge" {
    const points = [_]resource.testing.FailurePoint{
        .after_buffer_allocation,
        .after_parser_creation,
        .after_document_creation,
        .after_resource_initialization,
        .before_resource_publication,
    };

    inline for (points) |point| {
        try std.testing.expect(resource.testing.reset());
        var state = resource.DocumentState.empty();
        const status = resource.testing.openWithFailure(
            &state,
            std.testing.allocator,
            "{\"owned\":true}",
            point,
        );

        try std.testing.expect(status == .internal_failure);
        try std.testing.expectEqual(resource.Lifecycle.closed, state.lifecycleState());
        try std.testing.expectEqual(@as(u64, 0), state.generation.load(.acquire));
        try std.testing.expect(!state.hasOwnedNativeState());
        try std.testing.expect(resource.testing.waitForQuiescence(1_024));

        const snapshot = resource.testing.snapshot();
        const expected_destructions: usize = switch (point) {
            .after_buffer_allocation => 2,
            .after_parser_creation => 3,
            .after_document_creation,
            .after_resource_initialization,
            .before_resource_publication,
            => 4,
            .none => unreachable,
        };
        try std.testing.expectEqual(expected_destructions, snapshot.completed_destruction_events);
        try std.testing.expectEqual(@as(usize, 1), snapshot.completed_cleanup_events);
        try std.testing.expect(snapshot.isQuiescent());
        try std.testing.expect(snapshot.last_buffer_release_step > 0);

        switch (point) {
            .after_buffer_allocation => {
                try std.testing.expectEqual(@as(usize, 0), snapshot.last_parser_destruction_step);
                try std.testing.expectEqual(@as(usize, 0), snapshot.last_document_destruction_step);
            },
            .after_parser_creation => {
                try std.testing.expectEqual(@as(usize, 0), snapshot.last_document_destruction_step);
                try std.testing.expect(
                    snapshot.last_parser_destruction_step < snapshot.last_buffer_release_step,
                );
            },
            .after_document_creation,
            .after_resource_initialization,
            .before_resource_publication,
            => {
                try std.testing.expect(
                    snapshot.last_document_destruction_step <
                        snapshot.last_parser_destruction_step,
                );
                try std.testing.expect(
                    snapshot.last_parser_destruction_step < snapshot.last_buffer_release_step,
                );
            },
            .none => unreachable,
        }
    }
}

test "close blocks admission and waits for already admitted work" {
    try std.testing.expect(resource.testing.reset());
    var state = resource.DocumentState.empty();
    try std.testing.expect(state.openOwned(std.testing.allocator, "[1,2,3]") == .ok);

    const admission = state.tryAdmit().?;
    try std.testing.expectEqual(@as(u64, 1), admission.generation);
    try std.testing.expectEqual(@as(usize, 1), resource.testing.snapshot().admitted_operations);

    try std.testing.expectEqual(resource.CloseClaim.cleanup_owner, state.beginClose());
    try std.testing.expectEqual(resource.Lifecycle.closing, state.lifecycleState());
    try std.testing.expectEqual(@as(u64, 2), state.generation.load(.acquire));
    try std.testing.expect(state.tryAdmit() == null);
    try std.testing.expect(!state.completeCleanup());

    state.releaseAdmission(admission);
    try std.testing.expectEqual(@as(usize, 0), state.admitted_operations.load(.acquire));
    try std.testing.expect(state.completeCleanup());
    try std.testing.expectEqual(resource.Lifecycle.closed, state.lifecycleState());
    try std.testing.expect(state.completeCleanup());

    const snapshot = resource.testing.snapshot();
    try std.testing.expectEqual(@as(usize, 4), snapshot.completed_destruction_events);
    try std.testing.expectEqual(@as(usize, 1), snapshot.completed_cleanup_events);
    try std.testing.expect(snapshot.isQuiescent());
    try std.testing.expect(
        snapshot.last_document_destruction_step < snapshot.last_parser_destruction_step,
    );
    try std.testing.expect(
        snapshot.last_parser_destruction_step < snapshot.last_buffer_release_step,
    );

    try std.testing.expect(state.openOwned(std.testing.allocator, "null") == .invalid_argument);
}

test "concurrent close has one winner and exactly-once object destruction" {
    // GCC's preloaded ASan runtime cannot unmap Zig 0.16's custom thread
    // stacks. The ordinary profile owns the race proof; sanitizer coverage
    // still runs every single-threaded destruction and guard-page case.
    if (c.simd_json_test_sanitizer_build() != 0) return error.SkipZigTest;

    try std.testing.expect(resource.testing.reset());
    var state = resource.DocumentState.empty();
    try std.testing.expect(state.openOwned(std.testing.allocator, "{\"race\":true}") == .ok);

    var winners = std.atomic.Value(usize).init(0);
    const Race = struct {
        fn run(target: *resource.DocumentState, winner_count: *std.atomic.Value(usize)) void {
            if (target.beginClose() == .cleanup_owner) {
                _ = winner_count.fetchAdd(1, .acq_rel);
            }
        }
    };

    var threads: [16]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Race.run, .{ &state, &winners });
    }
    for (&threads) |*thread| thread.join();

    try std.testing.expectEqual(@as(usize, 1), winners.load(.acquire));
    try std.testing.expectEqual(resource.Lifecycle.closing, state.lifecycleState());
    try std.testing.expectEqual(@as(u64, 2), state.generation.load(.acquire));
    try std.testing.expect(state.completeCleanup());
    try std.testing.expect(state.closeAndDestroy());

    const snapshot = resource.testing.snapshot();
    try std.testing.expectEqual(@as(usize, 4), snapshot.completed_destruction_events);
    try std.testing.expectEqual(@as(usize, 1), snapshot.completed_cleanup_events);
    try std.testing.expect(snapshot.isQuiescent());
}

test "parent retention and bounded accounting expose no resource contents" {
    try std.testing.expect(resource.testing.reset());
    resource.testing.retainParent();
    try std.testing.expectEqual(@as(usize, 1), resource.testing.snapshot().retained_parents);
    try std.testing.expect(!resource.testing.waitForQuiescence(8));

    resource.testing.releaseParent();
    try std.testing.expect(resource.testing.waitForQuiescence(1_024));
    const snapshot = resource.testing.snapshot();
    try std.testing.expect(snapshot.isQuiescent());
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention simd_json.document_resource.test_accounting simd_json.document_resource.input_lifetime simd_json.document_resource.partial_open_failure
