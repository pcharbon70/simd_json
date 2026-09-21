defmodule SimdJson.Native.BuildSmoke.Config do
  @moduledoc false

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
    :threaded_decode_fixture,
    :threaded_document_probe,
    :document_lifecycle,
    :document_projection_owner_state,
    :document_stream_reservation_probe,
    :execution_set_cleanup_rejection,
    :execution_snapshot,
    :native_pool_start_with_failure,
    :native_pool_submit_fixture,
    :native_pool_pause_workers,
    :native_pool_submit_monitored_fixture,
    :native_pool_cancel_fixture,
    :native_pool_request_state_fixture,
    :native_pool_abandon_monitor_fixture,
    :native_pool_serialization_fixture,
    :native_pool_submit_serialized_fixture,
    :native_pool_close_serialization_fixture,
    :native_pool_serialization_state_fixture
  ]

  @production_nifs [
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
    native_pool_submit_open: [],
    native_pool_submit_cleanup: [],
    native_pool_submit_projection: [],
    native_pool_submit_decode: [],
    native_pool_submit_stream_binary_setup: [],
    native_pool_submit_stream_document_setup: [],
    native_pool_submit_stream_batch: [],
    stream_cursor_resource_close: [],
    threaded_stream_setup_fixture: [concurrency: :threaded],
    threaded_stream_binary_setup_fixture: [concurrency: :threaded],
    threaded_stream_batch_fixture: [concurrency: :threaded]
  ]

  @test_nifs @production_nifs ++
               [
                 native_pool_start_with_failure: [],
                 native_pool_submit_fixture: [],
                 native_pool_pause_workers: [],
                 native_pool_submit_monitored_fixture: [],
                 native_pool_cancel_fixture: [],
                 native_pool_request_state_fixture: [],
                 native_pool_abandon_monitor_fixture: [],
                 native_pool_serialization_fixture: [],
                 native_pool_submit_serialized_fixture: [],
                 native_pool_close_serialization_fixture: [],
                 native_pool_serialization_state_fixture: [],
                 document_resource_registration_smoke: [],
                 document_resource_fixture: [],
                 stream_cursor_resource_fixture: [],
                 stream_cursor_demand_reserve: [],
                 stream_cursor_demand_complete: [],
                 stream_cursor_demand_cancel: [],
                 stream_cursor_demand_snapshot: [],
                 projection_operation_inject_failure: [],
                 operation_configure_pause: [],
                 operation_release_pause: [],
                 admission_context: [],
                 operation_owner_matches: [],
                 threaded_context_smoke: [concurrency: :threaded],
                 threaded_decode_fixture: [concurrency: :threaded],
                 threaded_document_probe: [concurrency: :threaded],
                 document_lifecycle: [],
                 document_projection_owner_state: [],
                 document_stream_reservation_probe: [],
                 execution_set_cleanup_rejection: [],
                 execution_snapshot: []
               ]

  @direct_nifs [
    simdjson_version: 0,
    simdjson_padding: 0,
    runtime_implementation: 0,
    target_triple: 0,
    execution_generation: 0,
    execution_begin_shutdown: 0,
    native_pool_snapshot: 0,
    native_pool_stop: 0
  ]

  @marshalled_nifs [
    document_owner_state: 1,
    document_prepare_cleanup: 1,
    execution_resume: 0,
    native_pool_start: 2,
    native_pool_submit_cleanup: 2,
    native_pool_submit_decode: 1,
    native_pool_submit_open: 1,
    native_pool_submit_projection: 1,
    native_pool_submit_stream_batch: 4,
    native_pool_submit_stream_binary_setup: 5,
    native_pool_submit_stream_document_setup: 6,
    operation_admit: 4,
    operation_cancel: 1,
    operation_finish: 2,
    operation_metadata: 1,
    operation_owner_is: 2,
    projection_operation_admit: 5,
    projection_operation_release: 1,
    projection_operation_rollback: 1,
    stream_cursor_resource_close: 1
  ]

  @threaded_nifs [
    threaded_document_cleanup: 2,
    threaded_document_open: 1,
    threaded_projection_execute: 1,
    threaded_stream_batch_fixture: 4,
    threaded_stream_binary_setup_fixture: 5,
    threaded_stream_setup_fixture: 6
  ]

  defmacro define_nifs! do
    test_hooks = Mix.env() == :test
    sanitizer_build = System.get_env("SIMD_JSON_SANITIZER") == "1"
    precompiled = SimdJson.Native.Precompiled.resolve!(mix_env: Mix.env())

    if precompiled do
      destination =
        Path.join([
          Mix.Project.app_path(),
          "priv",
          "lib",
          "Elixir.SimdJson.Native.BuildSmoke.so"
        ])

      SimdJson.Native.Precompiled.install!(precompiled, destination)
      precompiled_bindings()
    else
      SimdJson.Native.BuildGuard.validate!()
      source_bindings(test_hooks, sanitizer_build)
    end
  end

  defp source_bindings(test_hooks, sanitizer_build) do
    cxx_flags =
      [
        "-std=c++17",
        "-DSIMDJSON_AVX512_ALLOWED=0",
        "-DNDEBUG",
        "-fvisibility=hidden",
        "-fvisibility-inlines-hidden"
      ] ++
        if sanitizer_build do
          ["-O1", "-g", "-fno-omit-frame-pointer", "-fsanitize=address,undefined"]
        else
          []
        end

    sanitizer_libraries =
      if sanitizer_build do
        [
          System.fetch_env!("SIMD_JSON_ASAN_LIBRARY"),
          System.fetch_env!("SIMD_JSON_UBSAN_LIBRARY")
        ]
      else
        []
      end

    options = [
      otp_app: :simd_json,
      zig_code_path: "./native/zig/build_smoke.zig",
      optimize: {:env, :safe},
      extra_modules: [
        worker_pool: {"./native/zig/worker_pool.zig", []},
        document_resource: {"./native/zig/document_resource.zig", []},
        projection_plan: {"./native/zig/projection_plan.zig", []},
        stream_cursor: {"./native/zig/stream_cursor.zig", []},
        decode_materializer: {"./native/zig/decode_materializer.zig", []}
      ],
      resources: [
        :DocumentResource,
        :StreamCursorResource,
        :OperationResource,
        :JoinCopiedTerm,
        :PoolRequestResource,
        :PoolSerializationResource
      ],
      callbacks: [
        on_load: :resource_on_load,
        on_upgrade: :resource_on_upgrade,
        on_unload: :resource_on_unload
      ],
      nifs: if(test_hooks, do: @test_nifs, else: @production_nifs),
      c: [
        include_dirs: ["./native/include", "./native/vendor/simdjson"],
        headers: [simd_json_abi: "./native/include/simd_json_nif_internal.h"],
        src: [
          {"../../../native/src/build_smoke.cpp", cxx_flags},
          {"../../../native/src/simd_json_abi.cpp", cxx_flags},
          {"../../../native/src/simd_json_projection.cpp", cxx_flags},
          {"../../../native/src/simd_json_stream_cursor.cpp", cxx_flags},
          {"../../../native/src/simd_json_decode_materializer.cpp", cxx_flags},
          {"../../../native/vendor/simdjson/simdjson.cpp", cxx_flags}
        ],
        link_lib: sanitizer_libraries,
        link_libcpp: true
      ]
    ]

    options = if test_hooks, do: options, else: Keyword.put(options, :ignore, @test_only_nifs)

    quote do
      use Zig, unquote(Macro.escape(options))
    end
  end

  defp precompiled_bindings do
    direct = Enum.map(@direct_nifs, &direct_stub/1)
    marshalled = Enum.map(@marshalled_nifs, &marshalled_stub/1)
    threaded = Enum.map(@threaded_nifs, &threaded_stub/1)

    quote do
      @on_load :__load_nifs__

      @doc false
      def __load_nifs__ do
        path =
          :simd_json
          |> :code.priv_dir()
          |> Path.join("lib/Elixir.SimdJson.Native.BuildSmoke")
          |> String.to_charlist()

        :erlang.load_nif(path, 0)
      end

      unquote_splicing(direct)
      unquote_splicing(marshalled)
      unquote_splicing(threaded)
    end
  end

  defp direct_stub({name, arity}) do
    args = Macro.generate_arguments(arity, __MODULE__)

    quote do
      @doc false
      def unquote(name)(unquote_splicing(args)), do: :erlang.nif_error(:nif_not_loaded)
    end
  end

  defp marshalled_stub({name, arity}) do
    args = Macro.generate_arguments(arity, __MODULE__)
    nif_name = :"marshalled-#{name}"

    quote do
      defp unquote(nif_name)(unquote_splicing(args)), do: :erlang.nif_error(:nif_not_loaded)

      @doc false
      def unquote(name)(unquote_splicing(args)) do
        unquote(nif_name)(unquote_splicing(args))
      end
    end
  end

  defp threaded_stub({name, arity}) do
    args = Macro.generate_arguments(arity, __MODULE__)
    launch = :"#{name}-launch"
    join = :"#{name}-join"

    quote do
      defp unquote(launch)(unquote_splicing(args)), do: :erlang.nif_error(:nif_not_loaded)
      defp unquote(join)(_request), do: :erlang.nif_error(:nif_not_loaded)

      @doc false
      def unquote(name)(unquote_splicing(args)) do
        request = unquote(launch)(unquote_splicing(args))

        receive do
          {:done, ^request} -> unquote(join)(request)
          {:error, ^request} -> raise "thread for function #{unquote(name)} failed during launch"
        end
      end
    end
  end
end

defmodule SimdJson.Native.BuildSmoke do
  @moduledoc false

  require SimdJson.Native.BuildSmoke.Config
  SimdJson.Native.BuildSmoke.Config.define_nifs!()

  # covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.target_qualification
end
