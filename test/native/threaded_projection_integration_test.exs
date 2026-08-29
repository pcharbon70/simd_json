defmodule SimdJson.Native.ThreadedProjectionIntegrationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ProjectionOperation
  alias SimdJson.Native.ThreadedOperation
  alias SimdJson.Projection

  @projection_boundaries [
    :before_plan_compilation,
    :before_cursor_access,
    :during_traversal,
    :before_term_construction,
    :during_term_construction,
    :before_delivery
  ]
  @heartbeat_period_ms 2
  @heartbeat_budget_microseconds 500_000
  @scheduler_fixture_bytes 4 * 1_024 * 1_024
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

    on_exit(fn ->
      reset_runtime!()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.generation_and_resource_retention simd_json.projection_execution.binary_operation_lifetime simd_json.projection_engine.single_beam_boundary simd_json.projection_engine.transactional_conversion
  test "binary and document projections complete out of order without crossing results", %{
    baseline: baseline
  } do
    parent = self()
    admission_before = ThreadedOperation.admission_snapshot_for_test()

    {binary_caller, binary_monitor} =
      spawn_monitor(fn ->
        source = ~s({"binary":11,"discard":"#{String.duplicate("b", 8_192)}"})

        result =
          ProjectionOperation.select_for_test(source, [{:binary, ["binary"]}],
            pause: {:before_delivery, parent}
          )

        send(parent, {:binary_projection_result, result})
      end)

    assert_receive {
                     :simd_json_native_boundary,
                     binary_request_ref,
                     :projection,
                     generation,
                     :before_delivery
                   },
                   5_000

    {document_owner, document_monitor} =
      spawn_monitor(fn -> correlated_document_owner(parent) end)

    assert_receive {:correlated_document, ^document_owner, %Document{} = document}, 5_000
    assert inspect(document) == "#SimdJson.Document<opaque>"

    send(document_owner, :select)

    assert_receive {
                     :simd_json_native_boundary,
                     document_request_ref,
                     :projection,
                     ^generation,
                     :before_delivery
                   },
                   5_000

    assert is_reference(binary_request_ref)
    assert is_reference(document_request_ref)
    refute binary_request_ref == document_request_ref
    assert generation == BuildSmoke.execution_generation()

    assert :ok = OperationCoordinator.release_pause(document_request_ref)

    assert_receive {:document_projection_result, {:ok, document_result}}, 5_000
    assert document_result == %{:document => 22, "copied" => "owned 雪"}

    refute_receive {:binary_projection_result, _result}, 50
    send(document_owner, :close)
    assert_receive {:correlated_document_closed, :ok, :ok}, 5_000
    assert_receive {:DOWN, ^document_monitor, :process, ^document_owner, :normal}, 5_000

    assert :ok = OperationCoordinator.release_pause(binary_request_ref)
    assert_receive {:binary_projection_result, {:ok, %{binary: 11}}}, 5_000
    assert_receive {:DOWN, ^binary_monitor, :process, ^binary_caller, :normal}, 5_000

    # Closing the source and dropping its owner cannot invalidate a copied
    # string that crossed the single correlated join boundary.
    document = nil
    churn = for byte <- 1..2_000, do: :binary.copy(<<rem(byte, 251)>>, 64)
    :erlang.garbage_collect(self())
    assert document == nil
    assert length(churn) == 2_000
    assert document_result["copied"] == "owned 雪"

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    admission_after = ThreadedOperation.admission_snapshot_for_test()

    assert admission_after.projection == admission_before.projection + 2
    assert final.projection_worker_entries == baseline.projection_worker_entries + 2

    assert final.completed_projection_deliveries ==
             baseline.completed_projection_deliveries + 2

    assert_idle(final, baseline)
  end

  # covers: simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.generation_and_resource_retention simd_json.projection_execution.close_interlock simd_json.projection_execution.native_memory_baseline simd_json.native_execution.caller_dies_while_running simd_json.native_execution.late_result_cleanup
  test "caller death at every projection boundary discards binary and document work", %{
    baseline: baseline
  } do
    before = BuildSmoke.execution_snapshot()

    for source_kind <- [:binary, :document], boundary <- @projection_boundaries do
      run_caller_death_case(source_kind, boundary)
      wait_for_quiescence()
      assert_idle(BuildSmoke.execution_snapshot(), baseline)
    end

    final = BuildSmoke.execution_snapshot()
    expected_operations = length(@projection_boundaries) * 2

    assert final.projection_worker_entries ==
             before.projection_worker_entries + expected_operations

    assert final.discarded_projection_deliveries ==
             before.discarded_projection_deliveries + expected_operations
  end

  # covers: simd_json.projection_execution.close_interlock simd_json.projection_execution.generation_and_resource_retention simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.native_memory_baseline simd_json.native_execution.shutdown_cleanup simd_json.native_execution.reload_cleanup simd_json.document_resource.gc_cleanup simd_json.document_resource.reverse_destruction
  test "shutdown cancels selecting documents and GC callback retry is generation isolated", %{
    baseline: baseline
  } do
    parent = self()
    old_generation = BuildSmoke.execution_generation()

    {owner, owner_monitor} =
      spawn_monitor(fn -> shutdown_document_owner(parent) end)

    assert_receive {:shutdown_document_ready, ^owner}, 5_000
    send(owner, :select)

    assert_receive {
                     :simd_json_native_boundary,
                     request_ref,
                     :projection,
                     ^old_generation,
                     :during_traversal
                   },
                   5_000

    assert is_reference(request_ref)
    assert :ok = Application.stop(:simd_json)

    assert_receive {:shutdown_projection_result, {:error, %Error{reason: :cancelled}}}, 5_000
    refute Process.whereis(OperationCoordinator)

    stopped_generation = BuildSmoke.execution_generation()
    assert stopped_generation > old_generation
    assert {:ok, _applications} = Application.ensure_all_started(:simd_json)

    resumed_generation = BuildSmoke.execution_generation()
    assert resumed_generation > stopped_generation

    true = BuildSmoke.execution_set_cleanup_rejection(true)
    send(owner, :drop_document)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}, 5_000

    wait_until(fn ->
      BuildSmoke.execution_snapshot().retained_failed_cleanup ==
        baseline.retained_failed_cleanup + 1
    end)

    retained = BuildSmoke.execution_snapshot()
    assert retained.live_documents == baseline.live_documents + 1
    assert retained.live_document_controls == baseline.live_document_controls + 1

    true = BuildSmoke.execution_set_cleanup_rejection(false)
    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)

    assert {:ok, %{generation: ^resumed_generation}} =
             ProjectionOperation.select_for_test(
               ~s({"generation":#{resumed_generation}}),
               [{:generation, ["generation"]}]
             )

    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.projection_execution.scheduler_qualification simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.native_memory_baseline simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback
  test "large concurrent success and failure projections preserve the preliminary heartbeat budget",
       %{baseline: baseline} do
    valid = large_object(@scheduler_fixture_bytes)
    malformed = binary_part(valid, 0, byte_size(valid) - 1)
    concurrency = min(max(System.schedulers_online(), 2), 4)
    {:ok, selected} = Projection.validate([{:target, ["target"]}])
    {:ok, missing} = Projection.validate([{:missing, ["missing"]}])
    admission_before = ThreadedOperation.admission_snapshot_for_test()
    before = BuildSmoke.execution_snapshot()

    cases =
      [:binary_valid, :binary_malformed, :binary_missing, :document_valid, :document_missing]
      |> Enum.flat_map(&List.duplicate(&1, concurrency))

    heartbeat_pid = start_heartbeat()

    results =
      cases
      |> Enum.map(fn kind ->
        Task.async(fn -> run_large_projection(kind, valid, malformed, selected, missing) end)
      end)
      |> Task.await_many(60_000)

    heartbeat = stop_heartbeat(heartbeat_pid)

    Enum.zip(cases, results)
    |> Enum.each(fn
      {kind, {:ok, %{result: result, diagnostics: diagnostics}}}
      when kind in [:binary_valid, :document_valid] ->
        assert result == %{target: 42}
        assert_threaded_diagnostics(diagnostics)

      {kind, {:error, %{reason: reason, diagnostics: diagnostics}}}
      when kind == :binary_malformed and reason in [:invalid_json, :unexpected_eof] ->
        assert_threaded_diagnostics(diagnostics)

      {kind, {:error, %{reason: :missing_field, diagnostics: diagnostics}}}
      when kind in [:binary_missing, :document_missing] ->
        assert_threaded_diagnostics(diagnostics)

      unexpected ->
        flunk("unexpected large projection result: #{inspect(unexpected)}")
    end)

    assert heartbeat.samples > 0
    assert heartbeat.max_interval_microseconds < @heartbeat_budget_microseconds

    wait_for_quiescence()
    final = BuildSmoke.execution_snapshot()
    admission_after = ThreadedOperation.admission_snapshot_for_test()
    expected_operations = length(cases)

    assert admission_after.projection == admission_before.projection + expected_operations

    assert final.projection_worker_entries ==
             before.projection_worker_entries + expected_operations

    assert final.completed_projection_deliveries ==
             before.completed_projection_deliveries + expected_operations

    assert_idle(final, baseline)

    IO.puts(
      "phase4_projection_scheduler " <>
        "concurrency=#{concurrency} fixture_bytes=#{byte_size(valid)} " <>
        "operations=#{expected_operations} heartbeat_samples=#{heartbeat.samples} " <>
        "heartbeat_max_us=#{heartbeat.max_interval_microseconds}"
    )
  end

  defp correlated_document_owner(parent) do
    source = ~s({"document":22,"copied":"owned 雪","discard":"#{String.duplicate("d", 8_192)}"})
    {:ok, document} = SimdJson.open(source)
    send(parent, {:correlated_document, self(), document})

    receive do
      :select -> :ok
    end

    result =
      ProjectionOperation.select_for_test(
        document,
        [{:document, ["document"]}, {"copied", ["copied"]}],
        pause: {:before_delivery, parent}
      )

    send(parent, {:document_projection_result, result})

    receive do
      :close -> :ok
    end

    first = SimdJson.close(document)
    second = SimdJson.close(document)
    send(parent, {:correlated_document_closed, first, second})
  end

  defp run_caller_death_case(source_kind, boundary) do
    parent = self()
    tag = make_ref()

    {caller, monitor} =
      spawn_monitor(fn ->
        case source_kind do
          :binary ->
            result =
              ProjectionOperation.select_for_test(
                large_object(256 * 1_024),
                [{:target, ["target"]}],
                pause: {boundary, parent}
              )

            send(parent, {:unexpected_projection_delivery, tag, result})

          :document ->
            {:ok, %Document{__resource__: resource} = document} =
              SimdJson.open(large_object(256 * 1_024))

            send(parent, {:caller_death_document, tag, resource})

            receive do
              {:run_projection, ^tag} -> :ok
            end

            result =
              ProjectionOperation.select_for_test(
                document,
                [{:target, ["target"]}],
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
          assert_receive {:caller_death_document, ^tag, resource}, 5_000
          send(caller, {:run_projection, tag})
          resource
      end

    assert_receive {
                     :simd_json_native_boundary,
                     request_ref,
                     :projection,
                     generation,
                     ^boundary
                   },
                   5_000

    assert is_reference(request_ref)
    assert generation == BuildSmoke.execution_generation()
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 5_000
    refute_receive {:unexpected_projection_delivery, ^tag, _result}, 10

    wait_for_projection_quiescence()

    if document_resource do
      assert :ok = ThreadedOperation.cleanup(document_resource)
    end
  end

  defp shutdown_document_owner(parent) do
    {:ok, document} = SimdJson.open(large_object(512 * 1_024))
    send(parent, {:shutdown_document_ready, self()})

    receive do
      :select -> :ok
    end

    result =
      ProjectionOperation.select_for_test(
        document,
        [{:target, ["target"]}],
        pause: {:during_traversal, parent}
      )

    send(parent, {:shutdown_projection_result, result})

    receive do
      :drop_document -> :ok
    end
  end

  defp run_large_projection(kind, valid, malformed, selected, missing) do
    case kind do
      :binary_valid ->
        ThreadedOperation.project(:binary, valid, selected, diagnostics: true)

      :binary_malformed ->
        ThreadedOperation.project(:binary, malformed, selected, diagnostics: true)

      :binary_missing ->
        ThreadedOperation.project(:binary, valid, missing, diagnostics: true)

      :document_valid ->
        run_document_projection(valid, selected)

      :document_missing ->
        run_document_projection(valid, missing)
    end
  end

  defp run_document_projection(source, normalized) do
    {:ok, %Document{__resource__: resource} = document} = SimdJson.open(source)

    try do
      ThreadedOperation.project(:document, resource, normalized, diagnostics: true)
    after
      assert :ok = SimdJson.close(document)
    end
  end

  defp assert_threaded_diagnostics(diagnostics) do
    assert diagnostics.worker_context == :threaded
    assert diagnostics.boundary_count >= 3
    assert diagnostics.compilation_nanoseconds >= 0
    assert diagnostics.traversal_nanoseconds >= 0
    assert diagnostics.term_construction_nanoseconds >= 0
  end

  defp start_heartbeat do
    spawn_link(fn -> heartbeat_loop(System.monotonic_time(:microsecond), 0, 0) end)
  end

  defp heartbeat_loop(previous, maximum, samples) do
    receive do
      {:stop, caller, reference} ->
        send(
          caller,
          {:heartbeat_stopped, reference, %{max_interval_microseconds: maximum, samples: samples}}
        )
    after
      @heartbeat_period_ms ->
        now = System.monotonic_time(:microsecond)
        heartbeat_loop(now, max(maximum, now - previous), samples + 1)
    end
  end

  defp stop_heartbeat(heartbeat_pid) do
    reference = make_ref()
    send(heartbeat_pid, {:stop, self(), reference})
    assert_receive {:heartbeat_stopped, ^reference, heartbeat}, 5_000
    heartbeat
  end

  defp large_object(minimum_bytes) do
    prefix = ~s({"target":42,"padding":")
    suffix = ~s(","tail":true})
    padding = String.duplicate("x", max(minimum_bytes - byte_size(prefix) - byte_size(suffix), 1))
    prefix <> padding <> suffix
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

  defp wait_for_projection_quiescence do
    wait_until(fn ->
      native = BuildSmoke.execution_snapshot()

      coordinator_live_requests() == 0 and native.live_projection_operations == 0 and
        native.retained_projection_binaries == 0 and
        native.retained_projection_documents == 0 and
        native.live_projection_environments == 0 and native.live_projection_plans == 0 and
        native.live_projection_slots == 0 and
        native.live_projection_temporary_document_graphs == 0
    end)
  end

  defp wait_for_quiescence do
    wait_until(fn ->
      native = BuildSmoke.execution_snapshot()

      coordinator_live_requests() == 0 and
        Enum.all?(@idle_gauges, &(Map.fetch!(native, &1) == 0))
    end)
  end

  defp coordinator_live_requests do
    if Process.whereis(OperationCoordinator) do
      OperationCoordinator.snapshot().live_requests
    else
      0
    end
  end

  defp wait_until(predicate, attempts \\ 1_000)

  defp wait_until(_predicate, 0) do
    flunk(
      "native execution did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(coordinator_snapshot())}"
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

  defp coordinator_snapshot do
    if Process.whereis(OperationCoordinator), do: OperationCoordinator.snapshot(), else: :stopped
  end
end
