defmodule SimdJson.Native.ThreadedAdmissionTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ThreadedOperation

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
