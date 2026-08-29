defmodule SimdJson.Qualification.LifecycleMemoryQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  @default_seed 260_829_001
  @caller_death_cases 20
  @explicit_documents 16
  @garbage_collected_documents 16
  @exiting_owner_documents 8
  @application_cycles 3
  @boundaries [
    :before_copy,
    :before_parse,
    :after_parse,
    :before_publication,
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
    :retained_failed_cleanup
  ]

  setup do
    reset_runtime!()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      reset_runtime!()
      wait_for_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.native_execution.caller_dies_while_running simd_json.native_execution.cancellation_boundaries simd_json.native_execution.retained_resources simd_json.native_execution.late_result_cleanup simd_json.native_execution.threaded_submission_failure simd_json.native_execution.no_fallback simd_json.native_execution.large_gc_teardown simd_json.native_execution.reload_cleanup simd_json.native_execution.shutdown_cleanup simd_json.document_resource.repeated_close simd_json.document_resource.non_owner_rejection simd_json.document_resource.gc_cleanup simd_json.document_resource.native_memory_baseline simd_json.document_resource.reverse_destruction
  # covers: simd_json.native_execution.threaded_cleanup simd_json.document_resource.single_owner simd_json.document_resource.lifecycle simd_json.document_resource.idempotent_close simd_json.document_resource.deferred_large_cleanup simd_json.document_api.open_contract simd_json.document_api.close_contract simd_json.document_api.structured_error simd_json.document_api.initial_error_reasons simd_json.document_api.close_and_non_owner
  test "bounded randomized teardown batches return every live gauge to baseline", %{
    baseline: baseline
  } do
    seed = lifecycle_seed()
    {boundaries, random_state} = randomized_boundaries(seed)

    run_caller_death_batch(boundaries, baseline)
    run_submission_failure_batch(baseline)
    run_mixed_lifecycle_batch(random_state, baseline)
    generations = run_application_cycle_batch(boundaries, baseline)

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert_idle(final, baseline)

    report = %{
      "schema_version" => 1,
      "source_revision" => source_revision(),
      "seed" => seed,
      "caller_death_cases" => @caller_death_cases,
      "caller_death_boundaries" => Enum.map(boundaries, &Atom.to_string/1),
      "explicit_documents" => @explicit_documents,
      "garbage_collected_documents" => @garbage_collected_documents,
      "exiting_owner_documents" => @exiting_owner_documents,
      "application_cycles" => @application_cycles,
      "application_generations" => generations,
      "native_baseline" => stringify_map(baseline),
      "native_final" => stringify_map(final),
      "result" => "all live native gauges returned to baseline after every batch"
    }

    write_evidence(report)

    IO.puts(
      "phase6_lifecycle seed=#{seed} caller_deaths=#{@caller_death_cases} " <>
        "explicit=#{@explicit_documents} gc=#{@garbage_collected_documents} " <>
        "exiting_owners=#{@exiting_owner_documents} app_cycles=#{@application_cycles}"
    )
  end

  defp run_caller_death_batch(boundaries, baseline) do
    boundaries
    |> Enum.with_index()
    |> Enum.each(fn {boundary, index} ->
      parent = self()
      valid = large_json(256 * 1_024)

      input =
        if rem(index, 2) == 1 and boundary in [:before_copy, :before_parse] do
          binary_part(valid, 0, byte_size(valid) - 1)
        else
          valid
        end

      assert {:ok, close_candidate} = SimdJson.open(~s({"close_around_boundary":#{index}}))
      close_before_caller_death? = rem(index, 2) == 0

      {caller, monitor} =
        spawn_monitor(fn ->
          result = ThreadedOperation.open(input, pause: {boundary, parent})

          send(parent, {:unexpected_qualification_delivery, boundary, result})
        end)

      assert_receive {
                       :simd_json_native_boundary,
                       request_ref,
                       :document_open,
                       generation,
                       ^boundary
                     },
                     5_000

      assert is_reference(request_ref)
      assert generation == BuildSmoke.execution_generation()

      if close_before_caller_death? do
        assert :ok = SimdJson.close(close_candidate)
      end

      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 5_000

      unless close_before_caller_death? do
        assert :ok = SimdJson.close(close_candidate)
      end

      refute_receive {:unexpected_qualification_delivery, ^boundary, _result}, 10
      wait_for_quiescence()
      assert_idle(BuildSmoke.execution_snapshot(), baseline)
    end)
  end

  defp run_submission_failure_batch(baseline) do
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, true)

    for _case <- 1..12 do
      assert {:error, %Error{reason: :native_failure}} = SimdJson.open(~s({"rejected":true}))
    end

    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)

    for case_index <- 1..12 do
      assert {:ok, document} = SimdJson.open(~s({"cleanup_rejection":#{case_index}}))
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, true)
      assert {:error, %Error{reason: :native_failure}} = SimdJson.close(document)
      :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
      assert :ok = SimdJson.close(document)
    end

    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)

    true = BuildSmoke.execution_set_cleanup_rejection(true)
    create_ephemeral_documents(1)
    force_garbage_collection()

    wait_until(fn ->
      BuildSmoke.execution_snapshot().retained_failed_cleanup ==
        baseline.retained_failed_cleanup + 1
    end)

    true = BuildSmoke.execution_set_cleanup_rejection(false)
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
  end

  defp run_mixed_lifecycle_batch(random_state, baseline) do
    completed_before = BuildSmoke.execution_snapshot().completed_document_cleanup

    {explicit_actions, _state} =
      Enum.map_reduce(1..@explicit_documents, random_state, fn index, state ->
        {repeat_close?, next_state} = random_boolean(state)
        repeat_close? = repeat_close? or rem(index, 4) == 0
        assert {:ok, %Document{} = document} = SimdJson.open(~s({"explicit":#{index}}))

        assert {:error, %Error{reason: :not_owner}} =
                 Task.async(fn -> SimdJson.close(document) end) |> Task.await()

        assert :ok = SimdJson.close(document)
        if repeat_close?, do: assert(:ok = SimdJson.close(document))
        {repeat_close?, next_state}
      end)

    create_ephemeral_documents(@garbage_collected_documents)
    force_garbage_collection()

    parent = self()

    owners =
      for owner_index <- 1..@exiting_owner_documents do
        spawn_monitor(fn ->
          assert {:ok, _document} = SimdJson.open(~s({"exiting_owner":#{owner_index}}))
          send(parent, {:exiting_owner_ready, self()})
        end)
      end

    Enum.each(owners, fn {owner, monitor} ->
      assert_receive {:exiting_owner_ready, ^owner}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 5_000
    end)

    assert Enum.any?(explicit_actions)
    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    assert_idle(final, baseline)

    assert final.completed_document_cleanup ==
             completed_before + @explicit_documents + @garbage_collected_documents +
               @exiting_owner_documents
  end

  defp run_application_cycle_batch(boundaries, baseline) do
    Enum.map(Enum.take(boundaries, @application_cycles), fn boundary ->
      generation = BuildSmoke.execution_generation()
      parent = self()

      {caller, monitor} =
        spawn_monitor(fn ->
          result =
            ThreadedOperation.open(large_json(128 * 1_024),
              pause: {boundary, parent}
            )

          send(parent, {:qualification_shutdown_result, self(), result})
        end)

      assert_receive {
                       :simd_json_native_boundary,
                       _request_ref,
                       :document_open,
                       ^generation,
                       ^boundary
                     },
                     5_000

      assert :ok = Application.stop(:simd_json)

      assert_receive {:qualification_shutdown_result, ^caller, {:error, %{reason: :cancelled}}},
                     5_000

      assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 5_000
      stopped_generation = BuildSmoke.execution_generation()
      assert stopped_generation > generation

      assert {:ok, _applications} = Application.ensure_all_started(:simd_json)
      resumed_generation = BuildSmoke.execution_generation()
      assert resumed_generation > stopped_generation

      assert {:ok, document} = SimdJson.open("null")
      assert :ok = SimdJson.close(document)
      wait_for_quiescence()
      assert_idle(BuildSmoke.execution_snapshot(), baseline)
      resumed_generation
    end)
  end

  defp randomized_boundaries(seed) do
    state = :rand.seed_s(:exsss, seed_tuple(seed))

    1..@caller_death_cases
    |> Enum.map_reduce(state, fn _index, current_state ->
      {position, next_state} = :rand.uniform_s(length(@boundaries), current_state)
      {Enum.at(@boundaries, position - 1), next_state}
    end)
  end

  defp random_boolean(state) do
    {value, next_state} = :rand.uniform_s(2, state)
    {value == 2, next_state}
  end

  defp seed_tuple(seed) do
    {
      rem(seed, 30_269) + 1,
      rem(div(seed, 30_269), 30_307) + 1,
      rem(div(seed, 30_269 * 30_307), 30_323) + 1
    }
  end

  defp lifecycle_seed do
    case System.get_env("SIMD_JSON_LIFECYCLE_SEED") do
      nil ->
        @default_seed

      configured ->
        case Integer.parse(configured) do
          {seed, ""} when seed > 0 -> seed
          _other -> raise "SIMD_JSON_LIFECYCLE_SEED must be a positive integer"
        end
    end
  end

  defp create_ephemeral_documents(count) do
    _documents =
      for index <- 1..count do
        assert {:ok, document} = SimdJson.open(~s({"garbage_collected":#{index}}))
        document
      end

    :ok
  end

  defp reset_runtime! do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    true = BuildSmoke.execution_set_cleanup_rejection(false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_open, false)
    :ok = OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
    :ok = OperationCoordinator.set_open_failure_for_test(nil)
    wait_for_quiescence()
  end

  defp force_garbage_collection do
    Enum.each(1..4, fn _ ->
      :erlang.garbage_collect(self())

      if coordinator = Process.whereis(OperationCoordinator) do
        :erlang.garbage_collect(coordinator)
      end
    end)
  end

  defp assert_idle(snapshot, baseline) do
    Enum.each(@idle_gauges, fn gauge ->
      assert Map.fetch!(snapshot, gauge) == Map.fetch!(baseline, gauge),
             "native gauge #{gauge} did not return to baseline"
    end)
  end

  defp write_evidence(report) do
    case System.get_env("SIMD_JSON_QUALIFICATION_DIR") do
      nil ->
        :ok

      directory ->
        File.mkdir_p!(directory)
        File.write!(Path.join(directory, "lifecycle.json"), [:json.encode(report), "\n"])
    end
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp source_revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      _other -> "unavailable"
    end
  end

  defp large_json(minimum_bytes) do
    element = ~s("0123456789abcdef",)
    repetitions = div(minimum_bytes, byte_size(element)) + 1
    "[" <> String.duplicate(element, repetitions) <> ~s("end"])
  end

  defp wait_for_quiescence do
    wait_until(fn ->
      native = BuildSmoke.execution_snapshot()
      coordinator = OperationCoordinator.snapshot()

      coordinator.live_requests == 0 and native.live_operations == 0 and
        native.retained_inputs == 0 and native.queued_operations == 0 and
        native.queued_cleanup == 0 and native.running_operations == 0 and
        native.live_documents == 0 and native.live_document_controls == 0 and
        native.dispatcher_queued_cleanup == 0 and
        native.dispatcher_active_cleanup == 0 and
        native.retained_failed_cleanup == 0
    end)
  end

  defp wait_until(predicate, attempts \\ 2_000)

  defp wait_until(_predicate, 0) do
    flunk(
      "native execution did not reach baseline: " <>
        "#{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_until(predicate, attempts) do
    force_garbage_collection()

    if predicate.() do
      :ok
    else
      Process.sleep(5)
      wait_until(predicate, attempts - 1)
    end
  end
end
