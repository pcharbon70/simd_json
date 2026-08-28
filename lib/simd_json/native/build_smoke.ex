defmodule SimdJson.Native.BuildSmoke do
  @moduledoc false

  require SimdJson.Native.BuildGuard
  SimdJson.Native.BuildGuard.assert_supported!()

  use Zig,
    otp_app: :simd_json,
    zig_code_path: "./native/zig/build_smoke.zig",
    optimize: {:env, :safe},
    nifs: [
      simdjson_version: [],
      simdjson_padding: [],
      runtime_implementation: [],
      target_triple: []
    ],
    c: [
      include_dirs: ["./native/include", "./native/vendor/simdjson"],
      src: [
        {"../../../native/src/build_smoke.cpp",
         [
           "-std=c++17",
           "-DSIMDJSON_AVX512_ALLOWED=0",
           "-DNDEBUG",
           "-fvisibility=hidden",
           "-fvisibility-inlines-hidden"
         ]},
        {"../../../native/src/simd_json_abi.cpp",
         [
           "-std=c++17",
           "-DSIMDJSON_AVX512_ALLOWED=0",
           "-DNDEBUG",
           "-fvisibility=hidden",
           "-fvisibility-inlines-hidden"
         ]},
        {"../../../native/vendor/simdjson/simdjson.cpp",
         [
           "-std=c++17",
           "-DSIMDJSON_AVX512_ALLOWED=0",
           "-DNDEBUG",
           "-fvisibility=hidden",
           "-fvisibility-inlines-hidden"
         ]}
      ],
      link_libcpp: true
    ]

  # covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.target_qualification
end
