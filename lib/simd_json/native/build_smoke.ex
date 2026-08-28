defmodule SimdJson.Native.BuildSmoke do
  @moduledoc false

  require SimdJson.Native.BuildGuard
  SimdJson.Native.BuildGuard.assert_supported!()

  use Zig,
    otp_app: :simd_json,
    zig_code_path: "./native/zig/build_smoke.zig",
    optimize: {:env, :safe},
    extra_modules: [document_resource: {"./native/zig/document_resource.zig", []}],
    resources: [:DocumentResource, :OperationResource],
    callbacks: [
      on_load: :resource_on_load,
      on_upgrade: :resource_on_upgrade,
      on_unload: :resource_on_unload
    ],
    nifs: [
      simdjson_version: [],
      simdjson_padding: [],
      runtime_implementation: [],
      target_triple: [],
      document_resource_registration_smoke: [],
      document_resource_fixture: [],
      operation_admit: [],
      operation_metadata: [],
      operation_cancel: [],
      operation_finish: [],
      operation_configure_pause: [],
      operation_release_pause: [],
      admission_context: [],
      operation_owner_matches: [],
      operation_owner_is: [],
      threaded_context_smoke: [concurrency: :threaded],
      threaded_document_open: [concurrency: :threaded],
      threaded_document_cleanup: [concurrency: :threaded],
      document_lifecycle: [],
      document_owner_state: [],
      execution_generation: [],
      execution_begin_shutdown: [],
      execution_resume: [],
      execution_set_cleanup_rejection: [],
      execution_snapshot: []
    ],
    c: [
      include_dirs: ["./native/include", "./native/vendor/simdjson"],
      headers: [simd_json_abi: "./native/include/simd_json_abi.h"],
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
