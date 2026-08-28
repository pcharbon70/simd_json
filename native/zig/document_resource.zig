const std = @import("std");

/// Instantiate the ownership layer with declarations translated from the
/// canonical C header. The Zigler root and native tests each supply that same
/// header module, so this file never duplicates C constants or layouts.
pub fn Implementation(comptime c: type) type {
    return struct {
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
                if (self.lifecycleState() != .closed or self.hasOwnedNativeState())
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
                @memcpy(owned[0..source.len], source);
                @memset(owned[source.len..capacity], 0);

                var parser: ?*c.simd_json_parser = null;
                var status = adaptStatus(c.simd_json_parser_create(&parser));
                if (status != .ok or parser == null) {
                    self.destroyOwned();
                    return if (status == .ok)
                        statusWithoutDiagnostics(.internal_failure)
                    else
                        status;
                }
                self.parser_handle = parser;

                var document: ?*c.simd_json_document = null;
                status = adaptStatus(c.simd_json_document_open(
                    parser.?,
                    owned.ptr,
                    @intCast(source.len),
                    @intCast(capacity),
                    &document,
                ));
                if (status != .ok or document == null) {
                    self.destroyOwned();
                    return if (status == .ok)
                        statusWithoutDiagnostics(.internal_failure)
                    else
                        status;
                }
                self.document_handle = document;
                self.generation.store(1, .release);
                self.lifecycle.store(@intFromEnum(Lifecycle.open), .release);
                return .ok;
            }

            /// Dependency-safe primitive used directly by native tests until
            /// Phase 3 adds the exactly-once lifecycle guard around it.
            pub fn destroyOwned(self: *DocumentState) void {
                if (self.document_handle) |document| {
                    c.simd_json_document_destroy(document);
                    self.document_handle = null;
                }
                if (self.parser_handle) |parser| {
                    c.simd_json_parser_destroy(parser);
                    self.parser_handle = null;
                }
                if (self.padded_input) |owned| {
                    if (self.allocator) |allocator| allocator.free(owned);
                    self.padded_input = null;
                }

                self.allocator = null;
                self.logical_length = 0;
                self.lifecycle.store(@intFromEnum(Lifecycle.closed), .release);
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

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.input_lifetime
