defmodule SimdJson.Native.BuildSmoke do
  @moduledoc false

  require SimdJson.Native.BuildGuard
  SimdJson.Native.BuildGuard.assert_supported!()

  @sanitizer_build System.get_env("SIMD_JSON_SANITIZER") == "1"
  @test_hooks Mix.env() == :test
  @test_only_nifs [
    :document_resource_registration_smoke,
    :document_resource_fixture,
    :stream_cursor_resource_fixture,
    :stream_cursor_demand_reserve,
    :stream_cursor_demand_complete,
    :stream_cursor_demand_cancel,
    :stream_cursor_demand_snapshot,
    :projection_operation_inject_failure,
    :operation_configure_pause,
    :operation_release_pause,
    :admission_context,
    :operation_owner_matches,
    :threaded_context_smoke,
    :threaded_document_probe,
    :document_lifecycle,
    :document_projection_owner_state,
    :document_stream_reservation_probe,
    :execution_set_cleanup_rejection,
    :execution_snapshot
  ]
  @cxx_flags [
               "-std=c++17",
               "-DSIMDJSON_AVX512_ALLOWED=0",
               "-DNDEBUG",
               "-fvisibility=hidden",
               "-fvisibility-inlines-hidden"
             ] ++
               if(@sanitizer_build,
                 do: [
                   "-O1",
                   "-g",
                   "-fno-omit-frame-pointer",
                   "-fsanitize=address,undefined"
                 ],
                 else: []
               )
  @sanitizer_libraries if(@sanitizer_build,
                         do: [
                           System.fetch_env!("SIMD_JSON_ASAN_LIBRARY"),
                           System.fetch_env!("SIMD_JSON_UBSAN_LIBRARY")
                         ],
                         else: []
                       )

  if @test_hooks do
    use Zig,
      otp_app: :simd_json,
      zig_code_path: "./native/zig/build_smoke.zig",
      optimize: {:env, :safe},
      extra_modules: [
        worker_pool: {"./native/zig/worker_pool.zig", []},
        document_resource: {"./native/zig/document_resource.zig", []},
        projection_plan: {"./native/zig/projection_plan.zig", []},
        stream_cursor: {"./native/zig/stream_cursor.zig", []}
      ],
      resources: [
        :DocumentResource,
        :StreamCursorResource,
        :OperationResource,
        :JoinCopiedTerm
      ],
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
        operation_admit: [],
        projection_operation_admit: [],
        projection_operation_rollback: [],
        projection_operation_release: [],
        operation_metadata: [],
        operation_cancel: [],
        operation_finish: [],
        operation_owner_is: [],
        threaded_document_open: [concurrency: :threaded],
        threaded_document_cleanup: [concurrency: :threaded],
        threaded_projection_execute: [concurrency: :threaded],
        document_owner_state: [],
        document_prepare_cleanup: [],
        execution_generation: [],
        execution_begin_shutdown: [],
        execution_resume: [],
        native_pool_start: [],
        native_pool_snapshot: [],
        native_pool_stop: [],
        document_resource_registration_smoke: [],
        document_resource_fixture: [],
        stream_cursor_resource_fixture: [],
        stream_cursor_resource_close: [],
        stream_cursor_demand_reserve: [],
        stream_cursor_demand_complete: [],
        stream_cursor_demand_cancel: [],
        stream_cursor_demand_snapshot: [],
        threaded_stream_setup_fixture: [concurrency: :threaded],
        threaded_stream_binary_setup_fixture: [concurrency: :threaded],
        threaded_stream_batch_fixture: [concurrency: :threaded],
        projection_operation_inject_failure: [],
        operation_configure_pause: [],
        operation_release_pause: [],
        admission_context: [],
        operation_owner_matches: [],
        threaded_context_smoke: [concurrency: :threaded],
        threaded_document_probe: [concurrency: :threaded],
        document_lifecycle: [],
        document_projection_owner_state: [],
        document_stream_reservation_probe: [],
        execution_set_cleanup_rejection: [],
        execution_snapshot: []
      ],
      c: [
        include_dirs: ["./native/include", "./native/vendor/simdjson"],
        headers: [simd_json_abi: "./native/include/simd_json_nif_internal.h"],
        src: [
          {"../../../native/src/build_smoke.cpp", @cxx_flags},
          {"../../../native/src/simd_json_abi.cpp", @cxx_flags},
          {"../../../native/src/simd_json_projection.cpp", @cxx_flags},
          {"../../../native/src/simd_json_stream_cursor.cpp", @cxx_flags},
          {"../../../native/vendor/simdjson/simdjson.cpp", @cxx_flags}
        ],
        link_lib: @sanitizer_libraries,
        link_libcpp: true
      ]
  else
    use Zig,
      otp_app: :simd_json,
      zig_code_path: "./native/zig/build_smoke.zig",
      optimize: {:env, :safe},
      ignore: @test_only_nifs,
      extra_modules: [
        worker_pool: {"./native/zig/worker_pool.zig", []},
        document_resource: {"./native/zig/document_resource.zig", []},
        projection_plan: {"./native/zig/projection_plan.zig", []},
        stream_cursor: {"./native/zig/stream_cursor.zig", []}
      ],
      resources: [
        :DocumentResource,
        :StreamCursorResource,
        :OperationResource,
        :JoinCopiedTerm
      ],
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
        operation_admit: [],
        projection_operation_admit: [],
        projection_operation_rollback: [],
        projection_operation_release: [],
        operation_metadata: [],
        operation_cancel: [],
        operation_finish: [],
        operation_owner_is: [],
        threaded_document_open: [concurrency: :threaded],
        threaded_document_cleanup: [concurrency: :threaded],
        threaded_projection_execute: [concurrency: :threaded],
        document_owner_state: [],
        document_prepare_cleanup: [],
        execution_generation: [],
        execution_begin_shutdown: [],
        execution_resume: [],
        native_pool_start: [],
        native_pool_snapshot: [],
        native_pool_stop: [],
        stream_cursor_resource_close: [],
        threaded_stream_setup_fixture: [concurrency: :threaded],
        threaded_stream_binary_setup_fixture: [concurrency: :threaded],
        threaded_stream_batch_fixture: [concurrency: :threaded]
      ],
      c: [
        include_dirs: ["./native/include", "./native/vendor/simdjson"],
        headers: [simd_json_abi: "./native/include/simd_json_nif_internal.h"],
        src: [
          {"../../../native/src/build_smoke.cpp", @cxx_flags},
          {"../../../native/src/simd_json_abi.cpp", @cxx_flags},
          {"../../../native/src/simd_json_projection.cpp", @cxx_flags},
          {"../../../native/src/simd_json_stream_cursor.cpp", @cxx_flags},
          {"../../../native/vendor/simdjson/simdjson.cpp", @cxx_flags}
        ],
        link_lib: @sanitizer_libraries,
        link_libcpp: true
      ]
  end

  # covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.target_qualification
end
