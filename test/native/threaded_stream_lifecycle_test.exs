defmodule SimdJson.Native.ThreadedStreamLifecycleTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  setup do
    for kind <- [:stream_setup, :stream_batch] do
      :ok = OperationCoordinator.set_submission_rejection_for_test(kind, false)
    end

    await_stream_quiescence()
    :ok
  end

  # covers: simd_json.stream_execution.correlated_batch_operations simd_json.stream_execution.threaded_stream_work simd_json.stream_execution.no_prefetch
  test "setup and demanded batches complete out of order without crossing correlation" do
    parent = self()

    setup =
      Task.async(fn ->
        ThreadedOperation.stream_probe(:stream_setup, "source", 91, 0,
          pause: {:before_copy, parent}
        )
      end)

    batch =
      Task.async(fn ->
        ThreadedOperation.stream_probe(:stream_batch, "cursor", 91, 1,
          pause: {:before_copy, parent}
        )
      end)

    boundaries =
      for _ <- 1..2, into: %{} do
        assert_receive {:simd_json_native_boundary, request_ref, kind, _generation, :before_copy},
                       2_000

        {kind, request_ref}
      end

    assert :ok = OperationCoordinator.release_pause(boundaries.stream_batch)
    assert {:ok, %{kind: :stream_batch, context: :threaded}} = Task.await(batch)
    refute Task.yield(setup, 20)
    assert :ok = OperationCoordinator.release_pause(boundaries.stream_setup)
    assert {:ok, %{kind: :stream_setup, context: :threaded}} = Task.await(setup)

    await_stream_quiescence()
    snapshot = BuildSmoke.execution_snapshot()
    assert snapshot.live_stream_setup_operations == 0
    assert snapshot.live_stream_batch_operations == 0
  end

  # covers: simd_json.stream_execution.early_halt_cleanup simd_json.stream_execution.cancellation_boundaries simd_json.stream_execution.native_memory_baseline
  test "caller death cancels paused stream work and returns operation graphs to baseline" do
    baseline = BuildSmoke.execution_snapshot()
    parent = self()

    caller =
      spawn(fn ->
        ThreadedOperation.stream_probe(:stream_batch, "cursor", 7, 4,
          pause: {:before_copy, parent}
        )
      end)

    monitor = Process.monitor(caller)

    assert_receive {:simd_json_native_boundary, _request_ref, :stream_batch, _generation,
                    :before_copy},
                   2_000

    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}, 2_000
    await_stream_quiescence()

    recovered = BuildSmoke.execution_snapshot()

    for gauge <- [
          :live_stream_setup_operations,
          :live_stream_batch_operations,
          :live_operations,
          :retained_inputs,
          :queued_operations,
          :running_operations
        ] do
      assert Map.fetch!(recovered, gauge) == Map.fetch!(baseline, gauge)
    end

    assert recovered.stream_discards == baseline.stream_discards + 1
  end

  # covers: simd_json.stream_execution.binary_cursor_graph simd_json.stream_execution.exclusive_document_cursor simd_json.stream_execution.single_in_flight_batch simd_json.stream_execution.native_memory_baseline
  test "real ABI v3 cursor advances one correlated threaded batch per demand" do
    {:ok, document} =
      SimdJson.open(~s([{"value":1},{"value":2},{"value":3}]))

    baseline = BuildSmoke.execution_snapshot()

    assert {:ok,
            %{
              status: :ok,
              kind: :stream_setup,
              worker_context: :threaded,
              cursor: cursor
            }} = ThreadedOperation.stream_setup_fixture(document.__resource__, 2, 1_024)

    assert is_reference(cursor)
    assert BuildSmoke.document_projection_owner_state(document.__resource__) == :consumed
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:ready, 0}

    assert {:ok,
            %{
              status: :ok,
              kind: :stream_batch,
              sequence: 0,
              produced_rows: 2,
              rows: [%{value: 1}, %{value: 2}],
              done: false
            }} = ThreadedOperation.stream_batch_fixture(cursor, 1, 0)

    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:ready, 1}

    assert {:ok,
            %{
              status: :ok,
              sequence: 1,
              produced_rows: 1,
              rows: [%{value: 3}],
              done: true
            }} = ThreadedOperation.stream_batch_fixture(cursor, 1, 1)

    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:done, 2}

    assert {:error, %{reason: :cursor_state, sequence: 2}} =
             ThreadedOperation.stream_batch_fixture(cursor, 1, 2)

    assert BuildSmoke.stream_cursor_resource_close(cursor)
    assert SimdJson.close(document) == :ok
    await_stream_quiescence()

    recovered = BuildSmoke.execution_snapshot()
    assert recovered.live_stream_cursor_resources == baseline.live_stream_cursor_resources
    assert recovered.retained_stream_cursor_parents == baseline.retained_stream_cursor_parents
    assert recovered.stream_setup_worker_entries == baseline.stream_setup_worker_entries + 1
    assert recovered.stream_batch_worker_entries == baseline.stream_batch_worker_entries + 3
  end

  # covers: simd_json.stream_execution.binary_cursor_graph simd_json.stream_execution.generation_and_retention
  test "binary setup retains one unpublished native graph across demanded batches" do
    input = ~s([{"value":"alpha"},{"value":"beta"}])
    baseline = BuildSmoke.execution_snapshot()

    assert {:ok, %{cursor: cursor, status: :ok}} =
             ThreadedOperation.stream_binary_setup_fixture(input, 1, 1_024)

    input = nil
    :erlang.garbage_collect(self())
    assert input == nil

    assert {:ok, %{rows: [%{value: "alpha"}], done: false}} =
             ThreadedOperation.stream_batch_fixture(cursor, 1, 0)

    assert {:ok, %{rows: [%{value: "beta"}], done: true}} =
             ThreadedOperation.stream_batch_fixture(cursor, 1, 1)

    assert BuildSmoke.stream_cursor_resource_close(cursor)
    await_stream_quiescence()
    recovered = BuildSmoke.execution_snapshot()
    assert recovered.live_stream_cursor_resources == baseline.live_stream_cursor_resources
    assert recovered.retained_stream_cursor_parents == baseline.retained_stream_cursor_parents
  end

  # covers: simd_json.stream_execution.no_prefetch simd_json.stream_execution.early_halt_cleanup simd_json.stream_execution.cancellation_boundaries
  test "slow consumption performs no prefetch and early close does not scan the remainder" do
    input = ~s([{"value":1},{"value":2},{"value":3}])

    assert {:ok, %{cursor: cursor}} =
             ThreadedOperation.stream_binary_setup_fixture(input, 1, 1_024)

    assert {:ok, %{rows: [%{value: 1}], done: false}} =
             ThreadedOperation.stream_batch_fixture(cursor, 1, 0)

    paused = BuildSmoke.execution_snapshot()
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:ready, 1}
    Process.sleep(30)
    still_paused = BuildSmoke.execution_snapshot()
    assert still_paused.stream_batch_worker_entries == paused.stream_batch_worker_entries
    assert still_paused.live_stream_batch_operations == paused.live_stream_batch_operations
    assert BuildSmoke.stream_cursor_demand_snapshot(cursor) == {:ready, 1}

    assert BuildSmoke.stream_cursor_demand_cancel(cursor)
    assert BuildSmoke.stream_cursor_resource_close(cursor)
    await_stream_quiescence()
  end

  defp await_stream_quiescence(attempts \\ 400)

  defp await_stream_quiescence(0) do
    flunk("stream operations did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}")
  end

  defp await_stream_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and
         snapshot.live_stream_setup_operations == 0 and
         snapshot.live_stream_batch_operations == 0 and snapshot.running_operations == 0 do
      :ok
    else
      Process.sleep(5)
      await_stream_quiescence(attempts - 1)
    end
  end
end
