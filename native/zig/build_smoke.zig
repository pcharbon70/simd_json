const std = @import("std");
const beam = @import("beam");
const e = @import("erl_nif");
const c = @import("simd_json_abi");
const document_resource = @import("document_resource").Implementation(c);

extern fn simd_json_build_smoke_version() callconv(.c) u32;
extern fn simd_json_build_smoke_padding() callconv(.c) u32;
extern fn simd_json_build_smoke_runtime_implementation() callconv(.c) [*:0]const u8;

const DocumentResourcePayload = struct {
    native: document_resource.DocumentState,
    owner: beam.pid,
};

const DocumentResourceCallbacks = struct {
    pub fn dtor(payload: *DocumentResourcePayload) void {
        // Phase 3 deliberately publishes no resource containing parse state.
        // The callback therefore performs no input-dependent work or native
        // destruction. Phase 4 will attach the off-scheduler cleanup queue.
        _ = payload.native.lifecycle.load(.acquire);
    }
};

pub const DocumentResource = beam.Resource(
    DocumentResourcePayload,
    @import("root"),
    .{ .Callbacks = DocumentResourceCallbacks },
);

var module_loaded = std.atomic.Value(bool).init(false);

pub fn simdjson_version() u32 {
    return simd_json_build_smoke_version();
}

pub fn simdjson_padding() u32 {
    return simd_json_build_smoke_padding();
}

pub fn runtime_implementation() []const u8 {
    return std.mem.span(simd_json_build_smoke_runtime_implementation());
}

pub fn target_triple() []const u8 {
    return "x86_64-linux-gnu";
}

/// A bounded internal fixture: it allocates and releases one empty resource
/// record without copying or parsing caller input.
pub fn document_resource_registration_smoke() !bool {
    if (!module_loaded.load(.acquire)) return false;

    const owner = try beam.self(.{});
    const fixture = try DocumentResource.create(.{
        .native = document_resource.DocumentState.empty(),
        .owner = owner,
    }, .{ .released = false });
    defer fixture.release();

    return !fixture.__payload.native.hasOwnedNativeState();
}

/// Produces only an opaque reference for a bounded resource-registration test.
/// It is internal to the build module and is not a public document constructor.
pub fn document_resource_fixture() !DocumentResource {
    const owner = try beam.self(.{});
    return DocumentResource.create(.{
        .native = document_resource.DocumentState.empty(),
        .owner = owner,
    }, .{});
}

fn retainParent(parent: DocumentResource) void {
    parent.keep();
}

fn releaseParent(parent: DocumentResource) void {
    parent.release();
}

pub fn resource_on_load(
    env: beam.env,
    private_data: ?*?*anyopaque,
    load_info: e.ErlNifTerm,
) callconv(.c) c_int {
    _ = env;
    _ = private_data;
    _ = load_info;
    module_loaded.store(true, .release);
    return 0;
}

pub fn resource_on_upgrade(
    env: beam.env,
    private_data: ?*?*anyopaque,
    old_private_data: ?*?*anyopaque,
    load_info: e.ErlNifTerm,
) callconv(.c) c_int {
    _ = env;
    _ = private_data;
    _ = old_private_data;
    _ = load_info;
    module_loaded.store(true, .release);
    return 0;
}

pub fn resource_on_unload(env: beam.env, private_data: ?*anyopaque) callconv(.c) void {
    _ = env;
    _ = private_data;
    module_loaded.store(false, .release);
}

// covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.parent_retention
