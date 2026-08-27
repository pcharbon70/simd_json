const std = @import("std");

extern fn simd_json_build_smoke_version() callconv(.c) u32;
extern fn simd_json_build_smoke_padding() callconv(.c) u32;
extern fn simd_json_build_smoke_runtime_implementation() callconv(.c) [*:0]const u8;

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
