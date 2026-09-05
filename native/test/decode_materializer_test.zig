const std = @import("std");
const decode_module = @import("decode_materializer");
const c = @cImport({
    @cInclude("simd_json_abi.h");
});
const decode = decode_module.Implementation(c);

const Fixture = struct {
    storage: []u8,
    parser: ?*c.simd_json_parser,
    document: ?*c.simd_json_document,

    fn init() !Fixture {
        const source = "{\"a\":[],\"b\":[{},null],\"s\":\"x\\u0000\\u96ea\",\"t\":true,\"f\":false,\"d\":null,\"d\":[],\"i\":-9223372036854775808,\"u\":18446744073709551615,\"n\":1.25e2}";
        const capacity = source.len + @as(usize, @intCast(c.SIMD_JSON_REQUIRED_PADDING));
        const storage = try std.testing.allocator.alloc(u8, capacity);
        errdefer std.testing.allocator.free(storage);
        @memcpy(storage[0..source.len], source);
        @memset(storage[source.len..], 0);
        var parser: ?*c.simd_json_parser = null;
        if (c.simd_json_parser_create(&parser).code != c.SIMD_JSON_STATUS_OK)
            return error.ParserCreate;
        errdefer c.simd_json_parser_destroy(parser);
        var document: ?*c.simd_json_document = null;
        if (c.simd_json_document_open(parser, storage.ptr, source.len, capacity, &document).code !=
            c.SIMD_JSON_STATUS_OK) return error.DocumentOpen;
        return .{ .storage = storage, .parser = parser, .document = document };
    }

    fn deinit(self: *Fixture) void {
        c.simd_json_document_destroy(self.document);
        c.simd_json_parser_destroy(self.parser);
        std.testing.allocator.free(self.storage);
        self.* = undefined;
    }
};

const limits = decode.Limits{
    .depth = 32,
    .container_entries = 100,
    .string_bytes = 1024,
    .output_bytes = 4096,
};

test "opaque materializer transfers one result and deinitializes idempotently" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var materializer = try decode.OwnedMaterializer.init(fixture.document, limits);
    defer materializer.deinit();
    var result = try materializer.execute();
    defer result.deinit();
    const graph = try result.graph();
    try std.testing.expectEqual(@as(usize, 13), graph.nodes.len);
    try std.testing.expectEqual(@as(usize, 12), graph.edges.len);
    try std.testing.expectEqual(@as(usize, 15), graph.copied_bytes.len);
    try std.testing.expectEqual(c.SIMD_JSON_DECODE_NODE_SIGNED_INTEGER, graph.nodes[10].tag);
    try std.testing.expectEqual(c.SIMD_JSON_DECODE_NODE_UNSIGNED_INTEGER, graph.nodes[11].tag);
    try std.testing.expectEqual(c.SIMD_JSON_DECODE_NODE_DOUBLE, graph.nodes[12].tag);
    try std.testing.expectEqual(@as(?u64, 0), graph.root_node);
    try std.testing.expectError(error.Consumed, materializer.execute());
    result.deinit();
    result.deinit();
    materializer.deinit();
    materializer.deinit();
}

test "invalid limits never acquire a native owner" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var invalid = limits;
    invalid.depth = 0;
    try std.testing.expectError(
        error.InvalidArgument,
        decode.OwnedMaterializer.init(fixture.document, invalid),
    );
    try std.testing.expectError(
        error.InvalidArgument,
        decode.OwnedMaterializer.init(null, limits),
    );
}
