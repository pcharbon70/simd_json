defmodule SimdJson.Native.ThreadedTeardownTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  setup do
    {:ok, _applications} = Application.ensure_all_started(:simd_json)
    true = BuildSmoke.execution_set_cleanup_rejection(false)
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      {:ok, _applications} = Application.ensure_all_started(:simd_json)
      true = BuildSmoke.execution_set_cleanup_rejection(false)
      wait_for_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.native_execution.threaded_cleanup simd_json.document_resource.idempotent_close simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction
  test "concurrent explicit cleanup joins one native destruction", %{baseline: baseline} do
    assert {:ok, document} = ThreadedOperation.open(large_json(256 * 1_024))

    results =
      1..16
      |> Enum.map(fn _ -> Task.async(fn -> ThreadedOperation.cleanup(document) end) end)
      |> Task.await_many(5_000)

    assert results == List.duplicate(:ok, 16)
    assert BuildSmoke.document_lifecycle(document) == :closed

    document = nil
    wait_for_quiescence()
    assert document == nil

    snapshot = BuildSmoke.execution_snapshot()

    assert snapshot.completed_document_cleanup ==
             baseline.completed_document_cleanup + 1

    assert snapshot.live_documents == baseline.live_documents
    assert snapshot.live_document_controls == baseline.live_document_controls
  end

  # covers: simd_json.native_execution.threaded_cleanup simd_json.native_execution.large_gc_teardown simd_json.document_resource.deferred_large_cleanup simd_json.document_resource.gc_cleanup simd_json.document_resource.native_memory_baseline
  test "GC detaches large documents quickly and the dispatcher restores baseline", %{
    baseline: baseline
  } do
    input = large_json(1024 * 1_024)
    count = 8
    documents = create_documents(input, count)

    assert BuildSmoke.execution_snapshot().live_documents == baseline.live_documents + count
    assert length(documents) == count
    documents = nil

    {gc_microseconds, true} =
      :timer.tc(fn ->
        :erlang.garbage_collect(self())
      end)

    assert documents == nil
    # This is a preliminary callback bound, not Phase 6's scheduler budget.
    assert gc_microseconds < 500_000
    wait_for_quiescence()

    snapshot = BuildSmoke.execution_snapshot()
    assert snapshot.live_documents == baseline.live_documents
    assert snapshot.live_document_controls == baseline.live_document_controls

    assert snapshot.dispatcher_completed_cleanup >=
             baseline.dispatcher_completed_cleanup + count
  end

  # covers: simd_json.native_execution.no_fallback simd_json.native_execution.threaded_cleanup simd_json.document_resource.deferred_large_cleanup simd_json.document_resource.gc_cleanup
  test "rejected callback handoff retains ownership until retry", %{baseline: baseline} do
    true = BuildSmoke.execution_set_cleanup_rejection(true)
    create_abandoned_documents("null", 1)
    :erlang.garbage_collect(self())

    wait_until(fn ->
      BuildSmoke.execution_snapshot().retained_failed_cleanup ==
        baseline.retained_failed_cleanup + 1
    end)

    rejected = BuildSmoke.execution_snapshot()
    assert rejected.live_documents == baseline.live_documents + 1
    assert rejected.live_document_controls == baseline.live_document_controls + 1

    assert rejected.cleanup_submission_failures ==
             baseline.cleanup_submission_failures + 1

    true = BuildSmoke.execution_set_cleanup_rejection(false)
    wait_for_quiescence()

    recovered = BuildSmoke.execution_snapshot()
    assert recovered.live_documents == baseline.live_documents
    assert recovered.live_document_controls == baseline.live_document_controls
    assert recovered.retained_failed_cleanup == baseline.retained_failed_cleanup
  end

  # covers: simd_json.native_execution.shutdown_cleanup simd_json.native_execution.reload_cleanup simd_json.native_execution.cancellation_boundaries
  test "application stop drains a paused operation and restart creates a fresh generation" do
    old_generation = BuildSmoke.execution_generation()
    parent = self()

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        result =
          ThreadedOperation.open(large_json(128 * 1_024),
            pause: {:after_parse, parent}
          )

        send(parent, {:shutdown_open_result, result})
      end)

    assert_receive {
                     :simd_json_native_boundary,
                     request_ref,
                     :document_open,
                     ^old_generation,
                     :after_parse
                   },
                   2_000

    assert is_reference(request_ref)
    assert :ok = Application.stop(:simd_json)
    assert_receive {:shutdown_open_result, {:error, %{reason: :cancelled}}}, 2_000
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 2_000
    refute Process.whereis(OperationCoordinator)

    stopped_generation = BuildSmoke.execution_generation()
    assert stopped_generation > old_generation

    assert_raise ErlangError, fn ->
      ThreadedOperation.admit("rejected", :document_open, stopped_generation)
    end

    assert {:ok, _applications} = Application.ensure_all_started(:simd_json)
    assert BuildSmoke.execution_generation() > stopped_generation

    assert {:ok, document} = ThreadedOperation.open("null")
    assert :ok = ThreadedOperation.cleanup(document)
    document = nil
    wait_for_quiescence()
    assert document == nil
  end

  # covers: simd_json.native_execution.bounded_nif_entry simd_json.native_execution.threaded_cleanup simd_json.document_resource.deferred_large_cleanup
  test "resource callback contains only detach and dispatcher handoff" do
    source = File.read!("native/zig/build_smoke.zig")

    [destructor] =
      Regex.run(
        ~r/pub fn dtor\(payload: \*DocumentResourcePayload\) void \{(?<body>.*?)\n    \}/s,
        source,
        capture: :all_names
      )

    assert destructor =~ "detachForDeferredCleanup"
    assert destructor =~ "enqueueDetachedDocument"

    for forbidden <- [
          "completeCleanup",
          "closeAndDestroy",
          "simd_json_document_destroy",
          "simd_json_parser_destroy",
          "allocator.destroy",
          "while"
        ] do
      refute destructor =~ forbidden
    end
  end

  defp create_abandoned_documents(input, count) do
    _documents = create_documents(input, count)
    :ok
  end

  defp create_documents(input, count) do
    Enum.map(1..count, fn _ ->
      assert {:ok, document} = ThreadedOperation.open(input)
      document
    end)
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
        native.running_operations == 0 and native.live_documents == 0 and
        native.live_document_controls == 0 and
        native.dispatcher_queued_cleanup == 0 and
        native.dispatcher_active_cleanup == 0 and
        native.retained_failed_cleanup == 0
    end)
  end

  defp wait_until(predicate, attempts \\ 400)

  defp wait_until(_predicate, 0) do
    flunk(
      "native execution did not reach expected state: " <>
        "#{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_until(predicate, attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))

    if predicate.() do
      :ok
    else
      Process.sleep(5)
      wait_until(predicate, attempts - 1)
    end
  end
end
