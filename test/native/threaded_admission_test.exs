defmodule SimdJson.Native.ThreadedAdmissionTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ThreadedOperation

  # covers: simd_json.stream_execution.correlated_batch_operations simd_json.stream_execution.threaded_stream_work
  test "stream setup and batch operations retain distinct threaded correlation identities" do
    generation = SimdJson.Native.BuildSmoke.execution_generation()
    setup = ThreadedOperation.admit("setup", :stream_setup, generation)
    batch = ThreadedOperation.admit("batch", :stream_batch, generation)

    assert setup.kind == :stream_setup
    assert batch.kind == :stream_batch
    assert setup.request_ref != batch.request_ref

    refute ThreadedOperation.correlated?(setup, %{
             kind: :stream_batch,
             generation: generation,
             request_ref: setup.request_ref,
             cursor_generation: 0,
             batch_sequence: 0
           })

    for operation <- [setup, batch] do
      assert {:ok, result} =
               ThreadedOperation.submit(operation, fn ->
                 SimdJson.Native.BuildSmoke.threaded_context_smoke(operation.resource)
               end)

      assert result.context == :threaded
      assert ThreadedOperation.correlated?(operation, result)
      assert SimdJson.Native.BuildSmoke.operation_finish(operation.resource, :delivered)
    end
  end

  # covers: simd_json.stream_execution.lazy_setup simd_json.stream_execution.correlated_batch_operations simd_json.stream_execution.owner_first_admission
  test "coordinator admits one correlated threaded job for each demanded stream operation" do
    before = ThreadedOperation.admission_snapshot_for_test()

    assert {:ok, setup} = ThreadedOperation.stream_probe(:stream_setup, "source", 41, 0)
    assert setup.kind == :stream_setup
    assert setup.context == :threaded

    assert {:ok, batch} = ThreadedOperation.stream_probe(:stream_batch, "cursor", 41, 1)
    assert batch.kind == :stream_batch
    assert batch.context == :threaded

    after_snapshot = ThreadedOperation.admission_snapshot_for_test()
    assert after_snapshot.stream_setup == before.stream_setup + 1
    assert after_snapshot.stream_batch == before.stream_batch + 1
    assert after_snapshot.total == before.total + 2
  end

  test "rejected stream submission is discarded without entering threaded work" do
    alias SimdJson.Native.BuildSmoke
    alias SimdJson.Native.OperationCoordinator

    baseline = BuildSmoke.execution_snapshot()
    :ok = OperationCoordinator.set_submission_rejection_for_test(:stream_batch, true)

    assert {:error, %{reason: :native_failure, stage: :threaded_submission}} =
             ThreadedOperation.stream_probe(:stream_batch, "cursor", 7, 3)

    :ok = OperationCoordinator.set_submission_rejection_for_test(:stream_batch, false)
    Process.sleep(10)
    after_snapshot = BuildSmoke.execution_snapshot()
    assert after_snapshot.worker_entries == baseline.worker_entries
  end

  # covers: simd_json.native_execution.threaded_parse simd_json.native_execution.bounded_nif_entry simd_json.native_execution.request_correlation simd_json.native_execution.retained_resources
  test "pinned admission is synchronous and retained work executes as threaded" do
    assert BuildSmoke.admission_context() == :synchronous

    before = BuildSmoke.execution_snapshot()
    result = ThreadedOperation.smoke(:binary.copy("x", 1_024 * 1_024))

    assert result.context == :threaded
    assert result.owner_matches
    assert result.kind == :threaded_smoke
    assert result.generation == BuildSmoke.execution_generation()
    assert result.input_length == 1_024 * 1_024

    collect_operations()
    after_snapshot = BuildSmoke.execution_snapshot()

    assert after_snapshot.live_operations == before.live_operations
    assert after_snapshot.retained_inputs == before.retained_inputs
    assert after_snapshot.queued_operations == before.queued_operations
    assert after_snapshot.queued_cleanup == before.queued_cleanup
    assert after_snapshot.running_operations == before.running_operations
    assert after_snapshot.worker_entries == before.worker_entries + 1
    assert after_snapshot.delivered_results == before.delivered_results + 1
  end

  # covers: simd_json.native_execution.request_correlation simd_json.native_execution.late_result_cleanup
  test "native references, operation kinds, and generations cannot be confused" do
    generation = BuildSmoke.execution_generation()
    first = ThreadedOperation.admit("first", :threaded_smoke, generation)
    second = ThreadedOperation.admit("second", :document_open, generation)

    refute first.request_ref == second.request_ref

    refute ThreadedOperation.correlated?(first, %{kind: second.kind, generation: first.generation})

    refute ThreadedOperation.correlated?(first, %{
             kind: first.kind,
             generation: generation + 1
           })

    assert {first.request_ref, :threaded_smoke, generation, :queued} ==
             BuildSmoke.operation_metadata(first.resource)

    assert {second.request_ref, :document_open, generation, :queued} ==
             BuildSmoke.operation_metadata(second.resource)

    assert BuildSmoke.operation_finish(first.resource, :discarded)
    assert BuildSmoke.operation_finish(second.resource, :discarded)

    first = second = nil
    collect_operations()
    assert first == nil and second == nil
  end

  # covers: simd_json.native_execution.cancellation_boundaries simd_json.native_execution.late_result_cleanup
  test "a queued cancellation discards retained input without entering worker code" do
    before = BuildSmoke.execution_snapshot()
    operation = ThreadedOperation.admit(:binary.copy("cancel", 128 * 1_024), :threaded_smoke)

    assert :ok = ThreadedOperation.cancel(operation)

    assert {operation.request_ref, :threaded_smoke, BuildSmoke.execution_generation(),
            :cancelling} ==
             BuildSmoke.operation_metadata(operation.resource)

    assert_raise ErlangError, fn ->
      BuildSmoke.threaded_context_smoke(operation.resource)
    end

    assert BuildSmoke.operation_finish(operation.resource, :discarded)
    operation = nil
    collect_operations()
    assert operation == nil

    after_snapshot = BuildSmoke.execution_snapshot()
    assert after_snapshot.live_operations == before.live_operations
    assert after_snapshot.retained_inputs == before.retained_inputs
    assert after_snapshot.queued_operations == before.queued_operations
    assert after_snapshot.queued_cleanup == before.queued_cleanup
    assert after_snapshot.running_operations == before.running_operations
    assert after_snapshot.worker_entries == before.worker_entries
    assert after_snapshot.discarded_results == before.discarded_results + 1
  end

  # covers: simd_json.native_execution.no_fallback simd_json.native_execution.late_result_cleanup
  test "submission failure returns a structured internal status and discards retention" do
    before = BuildSmoke.execution_snapshot()
    operation = ThreadedOperation.admit("not submitted", :document_cleanup)

    assert {:error, %{reason: :native_failure, stage: :threaded_submission}} =
             ThreadedOperation.submit(operation, fn -> raise "injected submission rejection" end)

    operation = nil
    collect_operations()
    assert operation == nil

    after_snapshot = BuildSmoke.execution_snapshot()
    assert after_snapshot.live_operations == before.live_operations
    assert after_snapshot.retained_inputs == before.retained_inputs
    assert after_snapshot.queued_operations == before.queued_operations
    assert after_snapshot.queued_cleanup == before.queued_cleanup
    assert after_snapshot.worker_entries == before.worker_entries
    assert after_snapshot.discarded_results == before.discarded_results + 1
  end

  # covers: simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback simd_json.native_execution.threaded_parse
  test "source policy registers worker execution only as Zigler threaded work" do
    config = File.read!("lib/simd_json/native/build_smoke.ex")
    native = File.read!("native/zig/build_smoke.zig")
    qualification = File.read!(".spec/research/zigler_0_16_threaded_qualification.md")

    assert config =~ "threaded_context_smoke: [concurrency: :threaded]"
    refute config =~ "threaded_context_smoke: [concurrency: :dirty_cpu]"
    refute config =~ "threaded_context_smoke: [concurrency: :dirty_io]"
    assert native =~ "beam.copy(private_env, input)"
    refute native =~ "pub fn threaded_context_smoke(input: []const u8)"
    assert qualification =~ ~r/does\s+not retain that binary after launch/
    assert qualification =~ "There is no normal- or dirty-scheduler fallback."
  end

  defp collect_operations(attempts \\ 50)

  defp collect_operations(0), do: :ok

  defp collect_operations(attempts) do
    :erlang.garbage_collect(self())

    if BuildSmoke.execution_snapshot().live_operations == 0 do
      :ok
    else
      Process.sleep(5)
      collect_operations(attempts - 1)
    end
  end
end
