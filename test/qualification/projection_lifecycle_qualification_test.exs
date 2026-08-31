defmodule SimdJson.Qualification.ProjectionLifecycleQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ProjectionOperation
  alias SimdJson.Native.ThreadedOperation

  @default_seed 260_831_006
  @boundaries [
    :before_plan_compilation,
    :before_cursor_access,
    :during_traversal,
    :before_term_construction,
    :during_term_construction,
    :before_delivery
  ]
  @idle_gauges [
    :live_operations,
    :retained_inputs,
    :queued_operations,
    :queued_cleanup,
    :running_operations,
    :live_documents,
    :live_document_controls,
    :dispatcher_queued_cleanup,
    :dispatcher_active_cleanup,
    :retained_failed_cleanup,
    :live_projection_operations,
    :retained_projection_binaries,
    :retained_projection_documents,
    :live_projection_environments,
    :live_projection_plans,
    :live_projection_slots,
    :live_projection_temporary_document_graphs
  ]

  setup do
    reset_runtime!()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn -> reset_runtime!() end)

    %{baseline: baseline}
  end

  # covers: simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.generation_and_resource_retention simd_json.projection_execution.binary_temporary_document simd_json.projection_execution.close_interlock simd_json.projection_execution.native_memory_baseline simd_json.projection_execution.submission_rejection_retry simd_json.projection_execution.caller_death_and_cancellation simd_json.projection_execution.document_one_shot simd_json.projection_execution.non_owner_and_close_race simd_json.native_execution.caller_dies_while_running simd_json.native_execution.late_result_cleanup simd_json.native_execution.shutdown_cleanup simd_json.native_execution.reload_cleanup
  @tag timeout: 180_000
  test "seeded projection lifetime matrix returns every live gauge to baseline", %{
    baseline: baseline
  } do
    seed = qualification_seed()
    source = large_object(512 * 1_024)
    boundary_cases = randomized_boundary_cases(seed)

    run_caller_death_batch(boundary_cases, source, baseline)
    run_failure_checkpoint_batch(source, baseline)
    run_submission_and_document_state_batch(source, baseline)
    run_result_retention_and_gc_batch(source, baseline)
    generations = run_application_generation_batch(source, baseline)

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert_idle(final, baseline)

    report = %{
      "schema_version" => 1,
      "source_revision" => git_identity("HEAD"),
      "source_tree" => git_identity("HEAD^{tree}"),
      "command" =>
        "mix test test/qualification/projection_lifecycle_qualification_test.exs --seed 0",
      "seed" => seed,
      "fixture_bytes" => byte_size(source),
      "fixture_sha256" => sha256(source),
      "caller_death_cases" =>
        Enum.map(boundary_cases, fn {kind, boundary} ->
          %{"source" => to_string(kind), "boundary" => to_string(boundary)}
        end),
      "failure_checkpoints" => %{
        "binary" => Enum.to_list(0..8),
        "document" => Enum.to_list(0..7)
      },
      "document_states" => ["fresh", "selecting", "consumed", "closing", "closed"],
      "application_generations" => generations,
      "native_baseline" => stringify_map(baseline),
      "native_final" => stringify_map(final),
      "bounded_quiescence_timeout_ms" => 10_000,
      "unsupported" => [
        "repeated in-process shared-object unload; application stop/start is not evidence for OS library unload"
      ],
      "result" => "pass"
    }

    write_evidence("projection-lifecycle.json", report)

    IO.puts(
      "projection_lifecycle seed=#{seed} caller_deaths=#{length(boundary_cases)} " <>
        "failure_cases=#{9 + 8} generations=#{Enum.join(generations, ",")}"
    )
  end

  defp run_caller_death_batch(cases, source, baseline) do
    Enum.each(cases, fn {source_kind, boundary} ->
      parent = self()
      tag = make_ref()

      {caller, monitor} =
        spawn_monitor(fn ->
          case source_kind do
            :binary ->
              result =
                ProjectionOperation.select_for_test(source, [target: ["target"]],
                  pause: {boundary, parent}
                )

              send(parent, {:unexpected_projection_delivery, tag, result})

            :document ->
              {:ok, %Document{__resource__: resource} = document} = SimdJson.open(source)
              send(parent, {:qualification_document, tag, resource})

              receive do
                {:continue, ^tag} -> :ok
              end

              result =
                ProjectionOperation.select_for_test(document, [target: ["target"]],
                  pause: {boundary, parent}
                )

              send(parent, {:unexpected_projection_delivery, tag, result})
          end
        end)

      document_resource =
        case source_kind do
          :binary ->
            nil

          :document ->
            assert_receive {:qualification_document, ^tag, resource}, 5_000
            send(caller, {:continue, tag})
            resource
        end

      assert_receive {:simd_json_native_boundary, _request_ref, :projection, _generation,
                      ^boundary},
                     5_000

      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 5_000
      refute_receive {:unexpected_projection_delivery, ^tag, _result}, 10
      wait_for_projection_quiescence()

      if document_resource, do: assert(:ok = ThreadedOperation.cleanup(document_resource))
      wait_for_quiescence()
      assert_idle(BuildSmoke.execution_snapshot(), baseline)
    end)
  end

  defp run_failure_checkpoint_batch(source, baseline) do
    projection = [target: ["target"], padding: ["padding"], tail: ["tail"]]

    for successful_checkpoints <- 0..8 do
      assert {:error, %Error{reason: :out_of_memory}} =
               ProjectionOperation.select_for_test(source, projection,
                 failure_after: successful_checkpoints
               )
    end

    for successful_checkpoints <- 0..7 do
      assert {:ok, %Document{__resource__: resource} = document} = SimdJson.open(source)

      assert {:error, %Error{reason: :out_of_memory}} =
               ProjectionOperation.select_for_test(document, projection,
                 failure_after: successful_checkpoints
               )

      if successful_checkpoints < 2 do
        assert BuildSmoke.document_projection_owner_state(resource) == :fresh

        assert {:ok, %{target: 42, padding: _padding, tail: true}} =
                 SimdJson.select(document, projection)
      else
        assert BuildSmoke.document_projection_owner_state(resource) == :consumed
      end

      assert :ok = SimdJson.close(document)
      wait_for_quiescence()
      assert_idle(BuildSmoke.execution_snapshot(), baseline)
    end
  end

  defp run_submission_and_document_state_batch(source, baseline) do
    assert {:ok, %Document{__resource__: resource} = document} = SimdJson.open(source)
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, true)

    assert {:error, %Error{reason: :native_failure}} =
             SimdJson.select(document, target: ["target"])

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh
    assert {:ok, %{target: 42}} = SimdJson.select(document, target: ["target"])
    assert BuildSmoke.document_projection_owner_state(resource) == :consumed

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn -> SimdJson.select(document, target: ["target"]) end)
             |> Task.await()

    assert :ok = SimdJson.close(document)
    assert :ok = SimdJson.close(document)
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
  end

  defp run_result_retention_and_gc_batch(source, baseline) do
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        assert {:ok, result} = SimdJson.select(source, padding: ["padding"])
        assert :binary.referenced_byte_size(result.padding) == byte_size(result.padding)
        send(parent, :copied_result_verified)
      end)

    assert_receive :copied_result_verified, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 5_000

    _documents =
      for index <- 1..8 do
        assert {:ok, document} = SimdJson.open(~s({"ephemeral":#{index}}))
        document
      end

    Enum.each(1..4, fn _ -> :erlang.garbage_collect(self()) end)
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
  end

  defp run_application_generation_batch(source, baseline) do
    parent = self()
    initial = BuildSmoke.execution_generation()

    {caller, monitor} =
      spawn_monitor(fn ->
        result =
          ProjectionOperation.select_for_test(source, [target: ["target"]],
            pause: {:during_traversal, parent}
          )

        send(parent, {:generation_projection_result, result})
      end)

    assert_receive {:simd_json_native_boundary, _request_ref, :projection, ^initial,
                    :during_traversal},
                   5_000

    assert :ok = Application.stop(:simd_json)
    assert_receive {:generation_projection_result, {:error, %Error{reason: :cancelled}}}, 5_000
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 5_000

    stopped = BuildSmoke.execution_generation()
    assert stopped > initial
    assert {:ok, _applications} = Application.ensure_all_started(:simd_json)
    resumed = BuildSmoke.execution_generation()
    assert resumed > stopped

    true = BuildSmoke.execution_set_cleanup_rejection(true)
    create_dropped_document()

    wait_until(fn ->
      BuildSmoke.execution_snapshot().retained_failed_cleanup ==
        baseline.retained_failed_cleanup + 1
    end)

    true = BuildSmoke.execution_set_cleanup_rejection(false)
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
    assert {:ok, %{target: 42}} = SimdJson.select(source, target: ["target"])
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
    [initial, stopped, resumed]
  end

  defp create_dropped_document do
    assert {:ok, _document} = SimdJson.open(~s({"dropped":true}))
    :ok
  end

  defp randomized_boundary_cases(seed) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))
    cases = for kind <- [:binary, :document], boundary <- @boundaries, do: {kind, boundary}

    cases
    |> Enum.map_reduce(state, fn value, current_state ->
      {rank, next_state} = :rand.uniform_s(1_000_000, current_state)
      {{rank, value}, next_state}
    end)
    |> elem(0)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp qualification_seed do
    case System.get_env("SIMD_JSON_LIFECYCLE_SEED") do
      nil -> @default_seed
      configured -> parse_seed!(configured)
    end
  end

  defp parse_seed!(configured) do
    case Integer.parse(configured) do
      {seed, ""} when seed > 0 -> seed
      _other -> raise "SIMD_JSON_LIFECYCLE_SEED must be a positive integer"
    end
  end

  defp seed_tuple(seed) do
    {
      rem(seed, 30_269) + 1,
      rem(div(seed, 30_269), 30_307) + 1,
      rem(div(seed, 30_269 * 30_307), 30_323) + 1
    }
  end

  defp large_object(minimum_bytes) do
    prefix = ~s({"target":42,"padding":")
    suffix = ~s(","tail":true})
    padding = String.duplicate("x", max(minimum_bytes - byte_size(prefix) - byte_size(suffix), 1))
    prefix <> padding <> suffix
  end

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp git_identity(revision) do
    case System.cmd("git", ["rev-parse", revision], stderr_to_stdout: true) do
      {value, 0} -> String.trim(value)
      _other -> "unavailable"
    end
  end

  defp stringify_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp write_evidence(filename, report) do
    if directory = System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, filename), [:json.encode(report), "\n"])
    end
  end

  defp reset_runtime! do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    true = BuildSmoke.execution_set_cleanup_rejection(false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    wait_for_quiescence()
  end

  defp assert_idle(snapshot, baseline) do
    Enum.each(@idle_gauges, fn gauge ->
      assert Map.fetch!(snapshot, gauge) == Map.fetch!(baseline, gauge),
             "native gauge #{gauge} did not return to baseline"
    end)
  end

  defp wait_for_quiescence do
    wait_until(fn ->
      snapshot = BuildSmoke.execution_snapshot()
      coordinator = OperationCoordinator.snapshot()

      coordinator.live_requests == 0 and
        Enum.all?(@idle_gauges, &(Map.fetch!(snapshot, &1) == 0))
    end)
  end

  defp wait_for_projection_quiescence do
    wait_until(fn ->
      snapshot = BuildSmoke.execution_snapshot()
      coordinator = OperationCoordinator.snapshot()

      coordinator.live_requests == 0 and snapshot.live_projection_operations == 0 and
        snapshot.retained_projection_binaries == 0 and
        snapshot.retained_projection_documents == 0 and
        snapshot.live_projection_environments == 0 and snapshot.live_projection_plans == 0 and
        snapshot.live_projection_slots == 0 and
        snapshot.live_projection_temporary_document_graphs == 0
    end)
  end

  defp wait_until(predicate, attempts \\ 2_000)

  defp wait_until(_predicate, 0) do
    flunk(
      "projection lifecycle did not reach baseline: " <>
        "#{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_until(predicate, attempts) do
    :erlang.garbage_collect(self())

    if coordinator = Process.whereis(OperationCoordinator) do
      :erlang.garbage_collect(coordinator)
    end

    if predicate.() do
      :ok
    else
      Process.sleep(5)
      wait_until(predicate, attempts - 1)
    end
  end
end
