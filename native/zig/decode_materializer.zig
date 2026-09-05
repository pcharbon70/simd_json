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
            MaxDepthExceeded,
            MaxContainerEntriesExceeded,
            MaxStringBytesExceeded,
            MaxOutputBytesExceeded,
            NumberOutOfRange,
            InvalidJson,
            InvalidUtf8,
            UnexpectedEof,
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
                c.SIMD_JSON_STATUS_MAX_DEPTH_EXCEEDED => error.MaxDepthExceeded,
                c.SIMD_JSON_STATUS_MAX_CONTAINER_ENTRIES_EXCEEDED => error.MaxContainerEntriesExceeded,
                c.SIMD_JSON_STATUS_MAX_STRING_BYTES_EXCEEDED => error.MaxStringBytesExceeded,
                c.SIMD_JSON_STATUS_MAX_OUTPUT_BYTES_EXCEEDED => error.MaxOutputBytesExceeded,
                c.SIMD_JSON_STATUS_NUMBER_OUT_OF_RANGE => error.NumberOutOfRange,
                c.SIMD_JSON_STATUS_INVALID_JSON => error.InvalidJson,
                c.SIMD_JSON_STATUS_INVALID_UTF8 => error.InvalidUtf8,
                c.SIMD_JSON_STATUS_UNEXPECTED_EOF => error.UnexpectedEof,
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

                const nodes = if (view.nodes) |ptr| ptr[0..node_count] else &.{};
                const edges = if (view.edges) |ptr| ptr[0..edge_count] else &.{};
                const copied_bytes = if (view.copied_bytes) |ptr| ptr[0..byte_count] else &.{};
                for (nodes) |node| {
                    if (node.reserved != 0) return error.InvalidGraph;
                    switch (node.tag) {
                        c.SIMD_JSON_DECODE_NODE_OBJECT,
                        c.SIMD_JSON_DECODE_NODE_ARRAY,
                        => if (node.edge_offset > view.edge_count or
                            node.edge_count > view.edge_count - node.edge_offset)
                            return error.InvalidGraph,
                        c.SIMD_JSON_DECODE_NODE_STRING => {
                            if (node.edge_count != 0 or
                                node.value.bytes.offset > view.copied_byte_count or
                                node.value.bytes.length > view.copied_byte_count - node.value.bytes.offset)
                                return error.InvalidGraph;
                        },
                        c.SIMD_JSON_DECODE_NODE_SIGNED_INTEGER,
                        c.SIMD_JSON_DECODE_NODE_UNSIGNED_INTEGER,
                        c.SIMD_JSON_DECODE_NODE_DOUBLE,
                        c.SIMD_JSON_DECODE_NODE_TRUE,
                        c.SIMD_JSON_DECODE_NODE_FALSE,
                        c.SIMD_JSON_DECODE_NODE_NULL,
                        => if (node.edge_count != 0) return error.InvalidGraph,
                        else => return error.InvalidGraph,
                    }
                }
                for (edges) |edge| {
                    if (edge.reserved != 0 or edge.value_node >= view.node_count)
                        return error.InvalidGraph;
                    const unavailable = edge.key_offset == c.SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE and
                        edge.key_length == c.SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE;
                    if (!unavailable and
                        (edge.key_offset > view.copied_byte_count or
                            edge.key_length > view.copied_byte_count - edge.key_offset))
                        return error.InvalidGraph;
                    if (!unavailable and
                        (edge.key_offset == c.SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE or
                            edge.key_length == c.SIMD_JSON_DECODE_BYTE_RANGE_UNAVAILABLE))
                        return error.InvalidGraph;
                }

                return .{
                    .nodes = nodes,
                    .edges = edges,
                    .copied_bytes = copied_bytes,
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
                return self.executeCancellable(null);
            }

            pub fn executeCancellable(
                self: *OwnedMaterializer,
                cancellation: ?*const c.simd_json_cancellation_probe,
            ) Error!OwnedResult {
                const handle = self.handle orelse return error.InvalidArgument;
                var result: ?*c.simd_json_decode_result = null;
                const status = c.simd_json_decode_materializer_execute(handle, cancellation, &result);
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
