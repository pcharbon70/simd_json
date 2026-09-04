const std = @import("std");

/// Opaque materializer/result ownership for private ABI v4. Result slices are
/// borrowed only while OwnedResult retains its C owner.
pub fn Implementation(comptime c: type) type {
    return struct {
        pub const Limits = struct {
            depth: u64,
            container_entries: u64,
            string_bytes: u64,
            output_bytes: u64,
        };

        pub const Error = error{
            InvalidArgument,
            OutOfMemory,
            Cancelled,
            Consumed,
            NativeFailure,
            InvalidGraph,
        };

        pub const Graph = struct {
            nodes: []const c.simd_json_decode_node,
            edges: []const c.simd_json_decode_edge,
            copied_bytes: []const u8,
            root_node: ?u64,
        };

        fn statusError(code: c.simd_json_status_code) Error {
            return switch (code) {
                c.SIMD_JSON_STATUS_INVALID_ARGUMENT => error.InvalidArgument,
                c.SIMD_JSON_STATUS_OUT_OF_MEMORY => error.OutOfMemory,
                c.SIMD_JSON_STATUS_CANCELLED => error.Cancelled,
                c.SIMD_JSON_STATUS_CURSOR_CONSUMED => error.Consumed,
                else => error.NativeFailure,
            };
        }

        pub const OwnedResult = struct {
            handle: ?*c.simd_json_decode_result = null,

            pub fn empty() OwnedResult {
                return .{};
            }

            pub fn deinit(self: *OwnedResult) void {
                const handle = self.handle orelse return;
                self.handle = null;
                c.simd_json_decode_result_destroy(handle);
            }

            pub fn isAlive(self: *const OwnedResult) bool {
                return self.handle != null;
            }

            pub fn graph(self: *const OwnedResult) Error!Graph {
                const handle = self.handle orelse return error.InvalidArgument;
                var view = std.mem.zeroes(c.simd_json_decode_result_view);
                const status = c.simd_json_decode_result_read(handle, &view);
                if (status.code != c.SIMD_JSON_STATUS_OK)
                    return statusError(status.code);
                if ((view.nodes == null) != (view.node_count == 0) or
                    (view.edges == null) != (view.edge_count == 0) or
                    (view.copied_bytes == null) != (view.copied_byte_count == 0) or
                    view.reserved != 0)
                    return error.InvalidGraph;

                const node_count = std.math.cast(usize, view.node_count) orelse
                    return error.InvalidGraph;
                const edge_count = std.math.cast(usize, view.edge_count) orelse
                    return error.InvalidGraph;
                const byte_count = std.math.cast(usize, view.copied_byte_count) orelse
                    return error.InvalidGraph;
                if (node_count == 0 and view.root_node != std.math.maxInt(u64))
                    return error.InvalidGraph;
                if (node_count != 0 and view.root_node >= view.node_count)
                    return error.InvalidGraph;

                return .{
                    .nodes = if (view.nodes) |ptr| ptr[0..node_count] else &.{},
                    .edges = if (view.edges) |ptr| ptr[0..edge_count] else &.{},
                    .copied_bytes = if (view.copied_bytes) |ptr| ptr[0..byte_count] else &.{},
                    .root_node = if (node_count == 0) null else view.root_node,
                };
            }
        };

        pub const OwnedMaterializer = struct {
            handle: ?*c.simd_json_decode_materializer = null,

            pub fn init(document: ?*c.simd_json_document, limits: Limits) Error!OwnedMaterializer {
                var config = c.simd_json_decode_config{
                    .max_depth = limits.depth,
                    .max_container_entries = limits.container_entries,
                    .max_string_bytes = limits.string_bytes,
                    .max_output_bytes = limits.output_bytes,
                    .reserved = 0,
                };
                var handle: ?*c.simd_json_decode_materializer = null;
                const status = c.simd_json_decode_materializer_create(document, &config, &handle);
                if (status.code != c.SIMD_JSON_STATUS_OK or handle == null) {
                    if (handle) |unexpected| c.simd_json_decode_materializer_destroy(unexpected);
                    return statusError(status.code);
                }
                return .{ .handle = handle };
            }

            pub fn deinit(self: *OwnedMaterializer) void {
                const handle = self.handle orelse return;
                self.handle = null;
                c.simd_json_decode_materializer_destroy(handle);
            }

            pub fn execute(self: *OwnedMaterializer) Error!OwnedResult {
                const handle = self.handle orelse return error.InvalidArgument;
                var result: ?*c.simd_json_decode_result = null;
                const status = c.simd_json_decode_materializer_execute(handle, null, &result);
                if (status.code != c.SIMD_JSON_STATUS_OK or result == null) {
                    if (result) |unexpected| c.simd_json_decode_result_destroy(unexpected);
                    return statusError(status.code);
                }
                return .{ .handle = result };
            }
        };

        comptime {
            if (c.SIMD_JSON_ABI_VERSION != 4) @compileError("decode requires ABI v4");
            if (@sizeOf(c.simd_json_decode_config) != 40 or
                @sizeOf(c.simd_json_decode_node) != 40 or
                @sizeOf(c.simd_json_decode_edge) != 32 or
                @sizeOf(c.simd_json_decode_result_view) != 64)
                @compileError("ABI v4 decode layouts changed");
        }
    };
}
