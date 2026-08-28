const std = @import("std");

/// Instantiate the ownership layer with declarations translated from the
/// canonical C header. The Zigler root and native tests each supply that same
/// header module, so this file never duplicates C constants or layouts.
pub fn Implementation(comptime c: type) type {
    return struct {
        const test_build = @hasDecl(c, "simd_json_test_live_parser_count") and
            @hasDecl(c, "simd_json_test_live_document_count");

        pub const required_padding_bytes: usize = @intCast(c.SIMD_JSON_REQUIRED_PADDING);
        pub const input_alignment_bytes: usize = required_padding_bytes;
        pub const input_alignment: std.mem.Alignment = .fromByteUnits(input_alignment_bytes);

        pub const Diagnostics = struct {
            native_code: ?i32,
            byte_offset: ?u64,
        };

        /// Closed adaptation of the private C status domain. Unknown numeric
        /// values become internal failures rather than entering the BEAM.
        pub const NativeStatus = union(enum) {
            ok,
            invalid_json: Diagnostics,
            invalid_utf8: Diagnostics,
            unexpected_eof: Diagnostics,
            out_of_memory: Diagnostics,
            invalid_argument: Diagnostics,
            internal_failure: Diagnostics,
        };

        pub const Lifecycle = enum(u8) {
            open,
            closing,
            closed,
        };

        pub const CloseClaim = enum {
            cleanup_owner,
            closing,
            closed,
        };

        pub const OperationAdmission = struct {
            generation: u64,
        };

        const ConstructionFailurePoint = enum {
            none,
            after_buffer_allocation,
            after_parser_creation,
            after_document_creation,
            after_resource_initialization,
            before_resource_publication,
        };

        const TestSnapshot = struct {
            live_padded_buffers: usize,
            live_parser_handles: usize,
            live_document_handles: usize,
            live_resource_records: usize,
            retained_parents: usize,
            admitted_operations: usize,
            completed_destruction_events: usize,
            completed_cleanup_events: usize,
            shim_live_parsers: u64,
            shim_live_documents: u64,
            last_document_destruction_step: usize,
            last_parser_destruction_step: usize,
            last_buffer_release_step: usize,

            pub fn isQuiescent(self: TestSnapshot) bool {
                return self.live_padded_buffers == 0 and
                    self.live_parser_handles == 0 and
                    self.live_document_handles == 0 and
                    self.live_resource_records == 0 and
                    self.retained_parents == 0 and
                    self.admitted_operations == 0 and
                    self.shim_live_parsers == 0 and
                    self.shim_live_documents == 0;
            }
        };

        const Accounting = if (test_build) struct {
            var live_padded_buffers = std.atomic.Value(usize).init(0);
            var live_parser_handles = std.atomic.Value(usize).init(0);
            var live_document_handles = std.atomic.Value(usize).init(0);
            var live_resource_records = std.atomic.Value(usize).init(0);
            var retained_parents = std.atomic.Value(usize).init(0);
            var admitted_operations = std.atomic.Value(usize).init(0);
            var completed_destruction_events = std.atomic.Value(usize).init(0);
            var completed_cleanup_events = std.atomic.Value(usize).init(0);
            var destruction_sequence = std.atomic.Value(usize).init(0);
            var last_document_destruction_step = std.atomic.Value(usize).init(0);
            var last_parser_destruction_step = std.atomic.Value(usize).init(0);
            var last_buffer_release_step = std.atomic.Value(usize).init(0);

            fn destructionStep(destination: *std.atomic.Value(usize)) void {
                const step = destruction_sequence.fetchAdd(1, .acq_rel) + 1;
                destination.store(step, .release);
            }

            fn snapshot() TestSnapshot {
                return .{
                    .live_padded_buffers = live_padded_buffers.load(.acquire),
                    .live_parser_handles = live_parser_handles.load(.acquire),
                    .live_document_handles = live_document_handles.load(.acquire),
                    .live_resource_records = live_resource_records.load(.acquire),
                    .retained_parents = retained_parents.load(.acquire),
                    .admitted_operations = admitted_operations.load(.acquire),
                    .completed_destruction_events = completed_destruction_events.load(.acquire),
                    .completed_cleanup_events = completed_cleanup_events.load(.acquire),
                    .shim_live_parsers = c.simd_json_test_live_parser_count(),
                    .shim_live_documents = c.simd_json_test_live_document_count(),
                    .last_document_destruction_step = last_document_destruction_step.load(.acquire),
                    .last_parser_destruction_step = last_parser_destruction_step.load(.acquire),
                    .last_buffer_release_step = last_buffer_release_step.load(.acquire),
                };
            }

            fn resetEvents() void {
                completed_destruction_events.store(0, .release);
                completed_cleanup_events.store(0, .release);
                destruction_sequence.store(0, .release);
                last_document_destruction_step.store(0, .release);
                last_parser_destruction_step.store(0, .release);
                last_buffer_release_step.store(0, .release);
            }
        } else struct {};

        pub fn checkedCapacity(logical_length: u128) ?usize {
            if (logical_length > std.math.maxInt(usize) or
                logical_length > std.math.maxInt(u64)) return null;

            return std.math.add(
                usize,
                @intCast(logical_length),
                required_padding_bytes,
            ) catch null;
        }

        fn statusWithoutDiagnostics(comptime tag: std.meta.Tag(NativeStatus)) NativeStatus {
            const diagnostics = Diagnostics{ .native_code = null, .byte_offset = null };
            return switch (tag) {
                .ok => .ok,
                .invalid_json => .{ .invalid_json = diagnostics },
                .invalid_utf8 => .{ .invalid_utf8 = diagnostics },
                .unexpected_eof => .{ .unexpected_eof = diagnostics },
                .out_of_memory => .{ .out_of_memory = diagnostics },
                .invalid_argument => .{ .invalid_argument = diagnostics },
                .internal_failure => .{ .internal_failure = diagnostics },
            };
        }

        fn accountParentRetained() void {
            if (test_build) _ = Accounting.retained_parents.fetchAdd(1, .acq_rel);
        }

        fn accountParentReleased() void {
            if (test_build) {
                const previous = Accounting.retained_parents.fetchSub(1, .acq_rel);
                std.debug.assert(previous > 0);
            }
        }

        /// These hooks accompany the actual BEAM keep/release helpers in the
        /// Zigler root. They compile to no accounting in production builds.
        pub fn noteParentRetained() void {
            accountParentRetained();
        }

        pub fn noteParentReleased() void {
            accountParentReleased();
        }

        /// Native storage embedded in the opaque BEAM resource. The C handles
        /// are private fields and this module has no term-encoding helpers.
        pub const DocumentState = struct {
            allocator: ?std.mem.Allocator,
            padded_input: ?[]align(input_alignment_bytes) u8,
            logical_length: usize,
            parser_handle: ?*c.simd_json_parser,
            document_handle: ?*c.simd_json_document,
            lifecycle: std.atomic.Value(u8),
            generation: std.atomic.Value(u64),
            admitted_operations: std.atomic.Value(usize),
            cleanup_started: std.atomic.Value(bool),
            record_accounted: bool,

            /// Establish a fully destructible state before any fallible work.
            pub fn empty() DocumentState {
                return .{
                    .allocator = null,
                    .padded_input = null,
                    .logical_length = 0,
                    .parser_handle = null,
                    .document_handle = null,
                    .lifecycle = .init(@intFromEnum(Lifecycle.closed)),
                    .generation = .init(0),
                    .admitted_operations = .init(0),
                    .cleanup_started = .init(false),
                    .record_accounted = false,
                };
            }

            pub fn lifecycleState(self: *const DocumentState) Lifecycle {
                return @enumFromInt(self.lifecycle.load(.acquire));
            }

            pub fn hasOwnedNativeState(self: *const DocumentState) bool {
                return self.padded_input != null or
                    self.parser_handle != null or
                    self.document_handle != null;
            }

            /// The sole Milestone 1 route from caller memory to simdjson. It
            /// performs one copy into a 64-byte-aligned allocation and passes
            /// the logical length separately from its private capacity.
            pub fn openOwned(
                self: *DocumentState,
                allocator: std.mem.Allocator,
                source: []const u8,
            ) NativeStatus {
                return self.openOwnedWithFailure(allocator, source, .none);
            }

            fn openOwnedWithFailure(
                self: *DocumentState,
                allocator: std.mem.Allocator,
                source: []const u8,
                comptime failure: ConstructionFailurePoint,
            ) NativeStatus {
                if (self.lifecycleState() != .closed or
                    self.hasOwnedNativeState() or
                    self.generation.load(.acquire) != 0 or
                    self.admitted_operations.load(.acquire) != 0)
                    return statusWithoutDiagnostics(.invalid_argument);

                const capacity = checkedCapacity(source.len) orelse
                    return statusWithoutDiagnostics(.invalid_argument);
                const owned = allocator.alignedAlloc(
                    u8,
                    input_alignment,
                    capacity,
                ) catch return statusWithoutDiagnostics(.out_of_memory);

                self.allocator = allocator;
                self.padded_input = owned;
                self.logical_length = source.len;
                self.record_accounted = true;
                if (test_build) {
                    _ = Accounting.live_resource_records.fetchAdd(1, .acq_rel);
                    _ = Accounting.live_padded_buffers.fetchAdd(1, .acq_rel);
                }
                @memcpy(owned[0..source.len], source);
                @memset(owned[source.len..capacity], 0);

                if (failure == .after_buffer_allocation) {
                    self.rollbackConstruction();
                    return statusWithoutDiagnostics(.internal_failure);
                }

                var parser: ?*c.simd_json_parser = null;
                var status = adaptStatus(c.simd_json_parser_create(&parser));
                if (status != .ok or parser == null) {
                    self.rollbackConstruction();
                    return if (status == .ok)
                        statusWithoutDiagnostics(.internal_failure)
                    else
                        status;
                }
                self.parser_handle = parser;
                if (test_build) _ = Accounting.live_parser_handles.fetchAdd(1, .acq_rel);

                if (failure == .after_parser_creation) {
                    self.rollbackConstruction();
                    return statusWithoutDiagnostics(.internal_failure);
                }

                var document: ?*c.simd_json_document = null;
                status = adaptStatus(c.simd_json_document_open(
                    parser.?,
                    owned.ptr,
                    @intCast(source.len),
                    @intCast(capacity),
                    &document,
                ));
                if (status != .ok or document == null) {
                    self.rollbackConstruction();
                    return if (status == .ok)
                        statusWithoutDiagnostics(.internal_failure)
                    else
                        status;
                }
                self.document_handle = document;
                if (test_build) _ = Accounting.live_document_handles.fetchAdd(1, .acq_rel);

                if (failure == .after_document_creation) {
                    self.rollbackConstruction();
                    return statusWithoutDiagnostics(.internal_failure);
                }

                self.cleanup_started.store(false, .release);
                if (failure == .after_resource_initialization) {
                    self.rollbackConstruction();
                    return statusWithoutDiagnostics(.internal_failure);
                }

                self.generation.store(1, .release);
                if (failure == .before_resource_publication) {
                    self.rollbackConstruction();
                    return statusWithoutDiagnostics(.internal_failure);
                }

                self.lifecycle.store(@intFromEnum(Lifecycle.open), .release);
                return .ok;
            }

            fn rollbackConstruction(self: *DocumentState) void {
                self.releaseOwnedFields();
                self.generation.store(0, .release);
                self.cleanup_started.store(false, .release);
                self.lifecycle.store(@intFromEnum(Lifecycle.closed), .release);
            }

            /// Exactly one caller can perform the open-to-closing transition.
            /// Its generation increment invalidates every previously admitted
            /// or future child view before any owned field can be destroyed.
            pub fn beginClose(self: *DocumentState) CloseClaim {
                const previous = self.lifecycle.cmpxchgStrong(
                    @intFromEnum(Lifecycle.open),
                    @intFromEnum(Lifecycle.closing),
                    .acq_rel,
                    .acquire,
                );

                if (previous == null) {
                    _ = self.generation.fetchAdd(1, .acq_rel);
                    return .cleanup_owner;
                }

                return switch (@as(Lifecycle, @enumFromInt(previous.?))) {
                    .open => unreachable,
                    .closing => .closing,
                    .closed => .closed,
                };
            }

            /// Resource callbacks use only this bounded atomic detach. Phase 4
            /// will enqueue the returned cleanup ownership off-scheduler.
            pub fn detachForDeferredCleanup(self: *DocumentState) CloseClaim {
                return self.beginClose();
            }

            pub fn tryAdmit(self: *DocumentState) ?OperationAdmission {
                if (self.lifecycleState() != .open) return null;

                _ = self.admitted_operations.fetchAdd(1, .acq_rel);
                if (test_build) _ = Accounting.admitted_operations.fetchAdd(1, .acq_rel);

                const generation = self.generation.load(.acquire);
                if (self.lifecycleState() == .open and generation != 0) {
                    return .{ .generation = generation };
                }

                self.releaseAdmissionCount();
                return null;
            }

            pub fn releaseAdmission(
                self: *DocumentState,
                admission: OperationAdmission,
            ) void {
                std.debug.assert(admission.generation != 0);
                std.debug.assert(admission.generation <= self.generation.load(.acquire));
                self.releaseAdmissionCount();
            }

            fn releaseAdmissionCount(self: *DocumentState) void {
                const previous = self.admitted_operations.fetchSub(1, .acq_rel);
                std.debug.assert(previous > 0);
                if (test_build) {
                    const aggregate_previous = Accounting.admitted_operations.fetchSub(1, .acq_rel);
                    std.debug.assert(aggregate_previous > 0);
                }
            }

            /// The off-scheduler cleanup executor calls this after admission
            /// reaches zero. A second atomic guard prevents duplicate release
            /// even if multiple shutdown paths observe the detached state.
            pub fn completeCleanup(self: *DocumentState) bool {
                if (self.lifecycleState() == .closed) return true;
                if (self.lifecycleState() != .closing or
                    self.admitted_operations.load(.acquire) != 0) return false;

                if (self.cleanup_started.cmpxchgStrong(
                    false,
                    true,
                    .acq_rel,
                    .acquire,
                ) != null) {
                    return self.lifecycleState() == .closed;
                }

                self.releaseOwnedFields();
                self.lifecycle.store(@intFromEnum(Lifecycle.closed), .release);
                return true;
            }

            pub fn closeAndDestroy(self: *DocumentState) bool {
                return switch (self.beginClose()) {
                    .cleanup_owner => self.completeCleanup(),
                    .closing => false,
                    .closed => true,
                };
            }

            fn releaseOwnedFields(self: *DocumentState) void {
                if (self.document_handle) |document| {
                    c.simd_json_document_destroy(document);
                    self.document_handle = null;
                    if (test_build) {
                        const previous = Accounting.live_document_handles.fetchSub(1, .acq_rel);
                        std.debug.assert(previous > 0);
                        _ = Accounting.completed_destruction_events.fetchAdd(1, .acq_rel);
                        Accounting.destructionStep(&Accounting.last_document_destruction_step);
                    }
                }
                if (self.parser_handle) |parser| {
                    c.simd_json_parser_destroy(parser);
                    self.parser_handle = null;
                    if (test_build) {
                        const previous = Accounting.live_parser_handles.fetchSub(1, .acq_rel);
                        std.debug.assert(previous > 0);
                        _ = Accounting.completed_destruction_events.fetchAdd(1, .acq_rel);
                        Accounting.destructionStep(&Accounting.last_parser_destruction_step);
                    }
                }
                if (self.padded_input) |owned| {
                    if (self.allocator) |allocator| allocator.free(owned);
                    self.padded_input = null;
                    if (test_build) {
                        const previous = Accounting.live_padded_buffers.fetchSub(1, .acq_rel);
                        std.debug.assert(previous > 0);
                        _ = Accounting.completed_destruction_events.fetchAdd(1, .acq_rel);
                        Accounting.destructionStep(&Accounting.last_buffer_release_step);
                    }
                }

                self.allocator = null;
                self.logical_length = 0;
                if (self.record_accounted) {
                    self.record_accounted = false;
                    if (test_build) {
                        const previous = Accounting.live_resource_records.fetchSub(1, .acq_rel);
                        std.debug.assert(previous > 0);
                        _ = Accounting.completed_destruction_events.fetchAdd(1, .acq_rel);
                        _ = Accounting.completed_cleanup_events.fetchAdd(1, .acq_rel);
                    }
                }
            }

            pub fn ownedInputMatches(self: *const DocumentState, expected: []const u8) bool {
                const owned = self.padded_input orelse return false;
                return self.logical_length == expected.len and
                    std.mem.eql(u8, owned[0..self.logical_length], expected);
            }

            pub fn paddingIsInitialized(self: *const DocumentState) bool {
                const owned = self.padded_input orelse return false;
                for (owned[self.logical_length..]) |byte| {
                    if (byte != 0) return false;
                }
                return true;
            }

            pub fn inputIsAligned(self: *const DocumentState) bool {
                const owned = self.padded_input orelse return false;
                return @intFromPtr(owned.ptr) % input_alignment_bytes == 0;
            }

            /// Test-only structural probes. They compile only when called from
            /// a root that imported the guarded C test header.
            pub fn cDocumentUsesOwnedInputForTest(self: *const DocumentState) bool {
                const owned = self.padded_input orelse return false;
                const document = self.document_handle orelse return false;
                if (!@hasDecl(c, "simd_json_test_document_uses_input"))
                    @compileError("test hooks are not present in this build");
                return c.simd_json_test_document_uses_input(
                    document,
                    owned.ptr,
                    @intCast(self.logical_length),
                ) == 1;
            }

            pub fn revalidateForTest(self: *const DocumentState) NativeStatus {
                const document = self.document_handle orelse
                    return statusWithoutDiagnostics(.invalid_argument);
                if (!@hasDecl(c, "simd_json_test_document_revalidate"))
                    @compileError("test hooks are not present in this build");
                return adaptStatus(c.simd_json_test_document_revalidate(document));
            }
        };

        /// This namespace does not exist in a production instantiation. Its
        /// bounded values never include native addresses, allocation contents,
        /// or caller JSON.
        pub const testing = if (test_build) struct {
            pub const FailurePoint = ConstructionFailurePoint;
            pub const Snapshot = TestSnapshot;

            pub fn openWithFailure(
                state: *DocumentState,
                allocator: std.mem.Allocator,
                source: []const u8,
                comptime point: FailurePoint,
            ) NativeStatus {
                std.debug.assert(point != .none);
                return state.openOwnedWithFailure(allocator, source, point);
            }

            pub fn snapshot() Snapshot {
                return Accounting.snapshot();
            }

            pub fn waitForQuiescence(max_attempts: usize) bool {
                var attempt: usize = 0;
                while (attempt < max_attempts) : (attempt += 1) {
                    if (snapshot().isQuiescent()) return true;
                    std.atomic.spinLoopHint();
                }
                return snapshot().isQuiescent();
            }

            pub fn reset() bool {
                if (!snapshot().isQuiescent()) return false;
                Accounting.resetEvents();
                return true;
            }

            pub fn retainParent() void {
                accountParentRetained();
            }

            pub fn releaseParent() void {
                accountParentReleased();
            }
        } else struct {};

        pub fn adaptStatus(status: c.simd_json_status) NativeStatus {
            const diagnostics = Diagnostics{
                .native_code = if (status.native_code == c.SIMD_JSON_NATIVE_CODE_UNAVAILABLE)
                    null
                else
                    status.native_code,
                .byte_offset = if (status.byte_offset == c.SIMD_JSON_BYTE_OFFSET_UNAVAILABLE)
                    null
                else
                    status.byte_offset,
            };

            return switch (status.code) {
                c.SIMD_JSON_STATUS_OK => .ok,
                c.SIMD_JSON_STATUS_INVALID_JSON => .{ .invalid_json = diagnostics },
                c.SIMD_JSON_STATUS_INVALID_UTF8 => .{ .invalid_utf8 = diagnostics },
                c.SIMD_JSON_STATUS_UNEXPECTED_EOF => .{ .unexpected_eof = diagnostics },
                c.SIMD_JSON_STATUS_OUT_OF_MEMORY => .{ .out_of_memory = diagnostics },
                c.SIMD_JSON_STATUS_INVALID_ARGUMENT => .{ .invalid_argument = diagnostics },
                c.SIMD_JSON_STATUS_INTERNAL_FAILURE => .{ .internal_failure = diagnostics },
                else => .{ .internal_failure = diagnostics },
            };
        }

        comptime {
            if (@sizeOf(c.simd_json_status_code) != @sizeOf(i32))
                @compileError("C status code width differs from Zig i32");
            if (@typeInfo(c.simd_json_status_code).int.signedness != .signed)
                @compileError("C status code must remain signed");
            if (@sizeOf(c.simd_json_status) != 16)
                @compileError("C status layout changed");
            if (@alignOf(c.simd_json_status) != @alignOf(u64))
                @compileError("C status alignment changed");
            if (@offsetOf(c.simd_json_status, "code") != 0 or
                @offsetOf(c.simd_json_status, "native_code") != 4 or
                @offsetOf(c.simd_json_status, "byte_offset") != 8)
                @compileError("C status field offsets changed");

            const status_values = [_]c.simd_json_status_code{
                c.SIMD_JSON_STATUS_OK,
                c.SIMD_JSON_STATUS_INVALID_JSON,
                c.SIMD_JSON_STATUS_INVALID_UTF8,
                c.SIMD_JSON_STATUS_UNEXPECTED_EOF,
                c.SIMD_JSON_STATUS_OUT_OF_MEMORY,
                c.SIMD_JSON_STATUS_INVALID_ARGUMENT,
                c.SIMD_JSON_STATUS_INTERNAL_FAILURE,
            };
            for (status_values, 0..) |value, index| {
                for (status_values[index + 1 ..]) |other| {
                    if (value == other) @compileError("C status values must be unique");
                }
            }

            if (required_padding_bytes == 0 or !std.math.isPowerOfTwo(input_alignment_bytes))
                @compileError("the pinned padding-derived input alignment must be a non-zero power of two");
        }
    };
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention simd_json.document_resource.test_accounting simd_json.document_resource.input_lifetime simd_json.document_resource.partial_open_failure
