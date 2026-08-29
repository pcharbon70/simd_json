defmodule SimdJson.Native.ThreadedProjectionOperationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ProjectionOperation
  alias SimdJson.Native.ThreadedOperation
  alias SimdJson.Projection

  @completion_tag {OperationCoordinator, :threaded_completion}

  setup do
    wait_for_projection_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      OperationCoordinator.set_submission_rejection_for_test(:projection, false)
      wait_for_projection_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.generation_and_resource_retention simd_json.projection_engine.single_beam_boundary simd_json.projection_engine.internal_phase_timing
  test "one retained projection completes only its correlated threaded request", %{
    baseline: baseline
  } do
    parent = self()
    source = ~s({"account":{"id":41,"name":"snow 雪"},"ready":true})
    projection = [{:id, ["account", "id"]}, {"name", ["account", "name"]}]

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        result =
          ProjectionOperation.select_for_test(source, projection,
            pause: {:before_delivery, parent},
            diagnostics: true
          )

        send(parent, {:projection_result, result})
      end)

    assert_receive {
                     :simd_json_native_boundary,
                     request_ref,
                     :projection,
                     generation,
                     :before_delivery
                   },
                   2_000

    assert is_reference(request_ref)
    assert generation == BuildSmoke.execution_generation()
    assert OperationCoordinator.snapshot().live_requests == 1

    retained = BuildSmoke.execution_snapshot()
    assert retained.live_projection_operations == baseline.live_projection_operations + 1
    assert retained.retained_projection_binaries == baseline.retained_projection_binaries + 1
    assert retained.live_projection_environments == baseline.live_projection_environments + 1
    assert retained.projection_worker_entries == baseline.projection_worker_entries + 1

    for forged <- [
          {@completion_tag, :document_open, request_ref, generation, self(), %{}},
          {@completion_tag, :projection, request_ref, generation + 1, self(), %{}},
          {@completion_tag, :projection, make_ref(), generation, self(), %{}}
        ] do
      send(OperationCoordinator, forged)
    end

    refute_receive {:projection_result, _result}, 50
    assert :ok = OperationCoordinator.release_pause(request_ref)

    assert_receive {:projection_result,
                    {:ok,
                     %{
                       result: %{:id => 41, "name" => "snow 雪"},
                       diagnostics: diagnostics
                     }}},
                   2_000

    assert diagnostics.worker_context == :threaded
    assert diagnostics.boundary_count >= 6
    assert diagnostics.compilation_nanoseconds >= 0
    assert diagnostics.traversal_nanoseconds >= 0
    assert diagnostics.term_construction_nanoseconds >= 0
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 2_000

    wait_for_projection_quiescence()
    after_snapshot = BuildSmoke.execution_snapshot()
    assert_projection_baseline(after_snapshot, baseline)
    assert after_snapshot.projection_worker_entries == baseline.projection_worker_entries + 1

    assert after_snapshot.completed_projection_deliveries ==
             baseline.completed_projection_deliveries + 1
  end

  # covers: simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.generation_and_resource_retention
  test "projection admission carries a unique reference, kind, generation, and retained payload",
       %{
         baseline: baseline
       } do
    {:ok, normalized} = Projection.validate([{:value, ["value"]}])
    generation = BuildSmoke.execution_generation()

    assert :ok = admit_and_discard_two(normalized, generation)
    wait_for_projection_quiescence()

    after_snapshot = BuildSmoke.execution_snapshot()
    assert_projection_baseline(after_snapshot, baseline)
    assert after_snapshot.projection_worker_entries == baseline.projection_worker_entries
  end

  defp admit_and_discard_two(normalized, generation) do
    {:ok, first} =
      ThreadedOperation.admit_projection(
        ~s({"value":1}),
        normalized,
        :binary,
        self(),
        generation
      )

    {:ok, second} =
      ThreadedOperation.admit_projection(
        ~s({"value":2}),
        normalized,
        :binary,
        self(),
        generation
      )

    refute first.request_ref == second.request_ref

    assert {first.request_ref, :projection, generation, :queued} ==
             BuildSmoke.operation_metadata(first.resource)

    assert {second.request_ref, :projection, generation, :queued} ==
             BuildSmoke.operation_metadata(second.resource)

    refute ThreadedOperation.correlated?(first, %{kind: :document_open, generation: generation})
    refute ThreadedOperation.correlated?(first, %{kind: :projection, generation: generation + 1})

    assert BuildSmoke.projection_operation_release(first.resource)
    assert BuildSmoke.projection_operation_release(second.resource)
    assert BuildSmoke.operation_finish(first.resource, :discarded)
    assert BuildSmoke.operation_finish(second.resource, :discarded)
    :ok
  end

  # covers: simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.native_execution.no_fallback
  test "submission rejection does not enter projection worker code or fall back", %{
    baseline: baseline
  } do
    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, true)
    {:ok, normalized} = Projection.validate([{:value, ["value"]}])

    assert {:error, %{reason: :native_failure, stage: :threaded_submission}} =
             ThreadedOperation.project(:binary, ~s({"value":1}), normalized)

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    wait_for_projection_quiescence()

    after_snapshot = BuildSmoke.execution_snapshot()
    assert_projection_baseline(after_snapshot, baseline)
    assert after_snapshot.projection_worker_entries == baseline.projection_worker_entries

    assert after_snapshot.discarded_projection_deliveries ==
             baseline.discarded_projection_deliveries + 1
  end

  # covers: simd_json.projection_execution.threaded_projection simd_json.projection_engine.single_beam_boundary simd_json.native_execution.no_fallback
  test "projection execution is registered only as one Zigler-threaded entry" do
    config = File.read!("lib/simd_json/native/build_smoke.ex")
    coordinator = File.read!("lib/simd_json/native/operation_coordinator.ex")
    native = File.read!("native/zig/build_smoke.zig")

    assert config =~ "threaded_projection_execute: [concurrency: :threaded]"
    refute config =~ "threaded_projection_execute: [concurrency: :dirty_cpu]"
    refute config =~ "threaded_projection_execute: [concurrency: :dirty_io]"
    assert coordinator =~ "BuildSmoke.threaded_projection_execute(operation.resource)"
    assert native =~ "const execute_outcome = plan.execute(beam.allocator, native_document)"
    refute native =~ "pub fn threaded_projection_execute(source:"
  end

  defp assert_projection_baseline(snapshot, baseline) do
    for field <- [
          :live_operations,
          :retained_inputs,
          :queued_operations,
          :running_operations,
          :live_projection_operations,
          :retained_projection_binaries,
          :retained_projection_documents,
          :live_projection_environments,
          :live_projection_plans,
          :live_projection_slots
        ] do
      assert Map.fetch!(snapshot, field) == Map.fetch!(baseline, field),
             "#{field} did not return to its baseline"
    end
  end

  defp wait_for_projection_quiescence(attempts \\ 400)

  defp wait_for_projection_quiescence(0) do
    flunk(
      "threaded projection did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_projection_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and
         snapshot.live_projection_operations == 0 and snapshot.live_projection_plans == 0 and
         snapshot.live_projection_slots == 0 and snapshot.live_projection_environments == 0 and
         snapshot.retained_projection_binaries == 0 and
         snapshot.retained_projection_documents == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_projection_quiescence(attempts - 1)
    end
  end
end
