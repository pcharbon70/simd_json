defmodule SimdJson.Native.ThreadedDocumentOpenTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  @completion_tag {OperationCoordinator, :threaded_completion}
  @boundaries [
    :before_copy,
    :before_parse,
    :after_parse,
    :before_publication,
    :before_delivery
  ]

  setup do
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    on_exit(fn -> wait_for_quiescence() end)
    %{baseline: baseline}
  end

  # covers: simd_json.native_execution.threaded_parse simd_json.native_execution.retained_resources simd_json.document_resource.opaque_handle simd_json.document_resource.padded_owned_copy simd_json.document_resource.complete_ownership simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.input_lifetime
  test "threaded open publishes a parsed opaque resource and bounded cleanup closes it", %{
    baseline: baseline
  } do
    input = IO.iodata_to_binary(["{", ~s("threaded":true), "}"])
    assert {:ok, document} = ThreadedOperation.open(input)
    input = nil
    :erlang.garbage_collect(self())
    assert input == nil
    assert is_reference(document)
    assert BuildSmoke.document_lifecycle(document) == :open

    during = BuildSmoke.execution_snapshot()
    assert during.live_documents == baseline.live_documents + 1

    assert :ok = ThreadedOperation.cleanup(document)
    assert BuildSmoke.document_lifecycle(document) == :closed

    document = nil
    wait_for_quiescence()
    assert document == nil

    after_snapshot = BuildSmoke.execution_snapshot()
    assert after_snapshot.live_documents == baseline.live_documents

    assert after_snapshot.completed_document_cleanup ==
             baseline.completed_document_cleanup + 1
  end

  # covers: simd_json.native_execution.threaded_parse simd_json.native_execution.late_result_cleanup simd_json.document_resource.partial_open_failure
  test "parser failures deliver only stable bounded diagnostics and no document", %{
    baseline: baseline
  } do
    assert {:error,
            %{
              reason: :unexpected_eof,
              native_code: native_code,
              byte_offset: byte_offset
            }} = ThreadedOperation.open("[1,")

    assert is_integer(native_code)
    assert is_integer(byte_offset)
    wait_for_quiescence()
    assert BuildSmoke.execution_snapshot().live_documents == baseline.live_documents
  end

  # covers: simd_json.native_execution.caller_dies_while_running simd_json.native_execution.cancellation_boundaries simd_json.native_execution.retained_resources simd_json.native_execution.late_result_cleanup
  test "caller death at every native boundary cancels safely and restores baseline", %{
    baseline: baseline
  } do
    for boundary <- @boundaries do
      parent = self()

      {caller, caller_monitor} =
        spawn_monitor(fn ->
          result =
            ThreadedOperation.open(~s({"boundary":"#{boundary}"}),
              pause: {boundary, parent}
            )

          send(parent, {:unexpected_delivery, boundary, result})
        end)

      assert_receive {
                       :simd_json_native_boundary,
                       request_ref,
                       :document_open,
                       generation,
                       ^boundary
                     },
                     2_000

      assert is_reference(request_ref)
      assert generation == BuildSmoke.execution_generation()

      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}, 2_000
      refute_receive {:unexpected_delivery, ^boundary, _result}, 50
      wait_for_quiescence()

      snapshot = BuildSmoke.execution_snapshot()
      assert snapshot.live_documents == baseline.live_documents
      assert snapshot.live_operations == baseline.live_operations
      assert snapshot.retained_inputs == baseline.retained_inputs
      assert snapshot.running_operations == baseline.running_operations
    end
  end

  # covers: simd_json.native_execution.request_correlation simd_json.native_execution.result_reference_mismatch simd_json.native_execution.late_result_cleanup
  test "reverse completion and forged correlation data cannot select another caller" do
    parent = self()

    first =
      spawn(fn ->
        send(
          parent,
          {:open_result, :first,
           ThreadedOperation.open(~s({"order":1}), pause: {:before_delivery, parent})}
        )
      end)

    assert_receive {
                     :simd_json_native_boundary,
                     first_ref,
                     :document_open,
                     generation,
                     :before_delivery
                   },
                   2_000

    second =
      spawn(fn ->
        send(parent, {:open_result, :second, ThreadedOperation.open(~s({"order":2}))})
      end)

    assert_receive {:open_result, :second, {:ok, second_document}}, 2_000
    refute_receive {:open_result, :first, _result}, 50

    send(
      OperationCoordinator,
      {@completion_tag, :document_open, make_ref(), generation, self(),
       %{
         kind: :document_open,
         generation: generation,
         worker_context: :threaded,
         status: :ok,
         document: nil
       }}
    )

    send(
      OperationCoordinator,
      {@completion_tag, :document_open, first_ref, generation + 1, self(),
       %{
         kind: :document_open,
         generation: generation + 1,
         worker_context: :threaded,
         status: :ok,
         document: nil
       }}
    )

    refute_receive {:open_result, :first, _result}, 50
    assert :ok = OperationCoordinator.release_pause(first_ref)
    assert_receive {:open_result, :first, {:ok, first_document}}, 2_000

    assert :ok = ThreadedOperation.cleanup(first_document)
    assert :ok = ThreadedOperation.cleanup(second_document)

    assert is_pid(first)
    assert is_pid(second)
    wait_for_quiescence()
  end

  # covers: simd_json.native_execution.bounded_nif_entry simd_json.native_execution.threaded_parse simd_json.native_execution.no_fallback
  test "document parse and cleanup entrypoints are structurally threaded" do
    config = File.read!("lib/simd_json/native/build_smoke.ex")
    native = File.read!("native/zig/build_smoke.zig")

    assert config =~ "threaded_document_open: [concurrency: :threaded]"
    assert config =~ "threaded_document_cleanup: [concurrency: :threaded]"

    for name <- ["threaded_document_open", "threaded_document_cleanup"] do
      refute config =~ "#{name}: [concurrency: :dirty_cpu]"
      refute config =~ "#{name}: [concurrency: :dirty_io]"
    end

    assert native =~ "openOwnedCancellable"
    assert native =~ "record.inputBytes()"
    refute native =~ "pub fn threaded_document_open(input: []const u8)"
  end

  defp wait_for_quiescence(attempts \\ 200)

  defp wait_for_quiescence(0) do
    flunk(
      "native execution did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))

    native = BuildSmoke.execution_snapshot()
    coordinator = OperationCoordinator.snapshot()

    if coordinator.live_requests == 0 and native.live_operations == 0 and
         native.running_operations == 0 and native.queued_operations == 0 and
         native.live_documents == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
