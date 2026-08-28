defmodule SimdJson.DocumentApiTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation

  setup do
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    on_exit(fn -> wait_for_quiescence() end)
    %{baseline: baseline}
  end

  # covers: simd_json.document_api.open_contract simd_json.document_api.close_contract simd_json.document_api.opaque_document_type simd_json.document_api.open_and_close simd_json.document_resource.opaque_handle simd_json.document_resource.lifecycle simd_json.document_resource.idempotent_close simd_json.document_resource.repeated_close
  test "opens an opaque document and closes it exactly once", %{baseline: baseline} do
    input = ~s({"private":"marker-5-1"})
    assert {:ok, %Document{} = document} = SimdJson.open(input)
    assert inspect(document) == "#SimdJson.Document<opaque>"
    refute inspect(document) =~ input

    %Document{__resource__: resource} = document
    assert BuildSmoke.document_owner_state(resource) == :open
    assert :ok = SimdJson.close(document)
    assert BuildSmoke.document_owner_state(resource) == :closed

    after_first_close = BuildSmoke.execution_snapshot()
    assert after_first_close.completed_document_cleanup == baseline.completed_document_cleanup + 1

    assert :ok = SimdJson.close(document)
    after_second_close = BuildSmoke.execution_snapshot()
    assert after_second_close.worker_entries == after_first_close.worker_entries

    assert after_second_close.completed_document_cleanup ==
             after_first_close.completed_document_cleanup

    document = resource = nil
    wait_for_quiescence()
    assert document == nil and resource == nil
  end

  # covers: simd_json.document_api.binary_only simd_json.document_api.non_binary_argument simd_json.native_execution.bounded_nif_entry
  test "rejects every non-binary before native admission", %{baseline: baseline} do
    for invalid <- [nil, :json, 1, 1.0, [], ["null"], %{}, {}, make_ref()] do
      assert_raise ArgumentError, "expected JSON input to be a binary", fn ->
        SimdJson.open(invalid)
      end
    end

    snapshot = BuildSmoke.execution_snapshot()
    assert snapshot.live_operations == baseline.live_operations
    assert snapshot.worker_entries == baseline.worker_entries
    assert snapshot.live_documents == baseline.live_documents
  end

  # covers: simd_json.document_api.document_argument_validation simd_json.document_api.invalid_document_argument
  test "rejects invalid and forged document values before cleanup admission", %{
    baseline: baseline
  } do
    for invalid <- [nil, "document", %{}, make_ref(), %Document{__resource__: make_ref()}] do
      assert_raise ArgumentError, "expected a SimdJson.Document", fn ->
        SimdJson.close(invalid)
      end
    end

    operation = ThreadedOperation.admit(<<>>, :threaded_smoke)
    forged = %Document{__resource__: operation.resource}
    before_forged_close = BuildSmoke.execution_snapshot()

    assert_raise ArgumentError, "expected a SimdJson.Document", fn ->
      SimdJson.close(forged)
    end

    after_forged_close = BuildSmoke.execution_snapshot()
    assert after_forged_close.worker_entries == before_forged_close.worker_entries
    assert after_forged_close.live_operations == before_forged_close.live_operations

    assert BuildSmoke.operation_finish(operation.resource, :discarded)
    operation = forged = nil
    wait_for_quiescence()
    assert operation == nil and forged == nil

    snapshot = BuildSmoke.execution_snapshot()
    assert snapshot.live_documents == baseline.live_documents
    assert snapshot.live_document_controls == baseline.live_document_controls
  end

  # covers: simd_json.document_api.close_contract simd_json.document_api.close_and_non_owner simd_json.document_resource.single_owner simd_json.document_resource.non_owner_rejection
  test "non-owner close is rejected before open and closed lifecycle state" do
    assert {:ok, %Document{} = document} = SimdJson.open("null")
    %Document{__resource__: resource} = document
    generation = BuildSmoke.execution_generation()
    before = BuildSmoke.execution_snapshot()

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn -> SimdJson.close(document) end) |> Task.await()

    after_rejection = BuildSmoke.execution_snapshot()
    assert BuildSmoke.document_lifecycle(resource) == :open
    assert BuildSmoke.execution_generation() == generation
    assert after_rejection.worker_entries == before.worker_entries
    assert after_rejection.completed_document_cleanup == before.completed_document_cleanup

    assert :ok = SimdJson.close(document)

    before_closed_rejection = BuildSmoke.execution_snapshot()

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn -> SimdJson.close(document) end) |> Task.await()

    after_closed_rejection = BuildSmoke.execution_snapshot()
    assert BuildSmoke.document_lifecycle(resource) == :closed
    assert BuildSmoke.execution_generation() == generation
    assert after_closed_rejection.worker_entries == before_closed_rejection.worker_entries

    assert after_closed_rejection.completed_document_cleanup ==
             before_closed_rejection.completed_document_cleanup

    assert :ok = SimdJson.close(document)
    document = resource = nil
    wait_for_quiescence()
    assert document == nil and resource == nil
  end

  # covers: simd_json.document_api.open_contract simd_json.document_api.structured_error
  test "malformed JSON returns a structured error and no partial document" do
    assert {:error,
            %Error{
              reason: :unexpected_eof,
              byte_offset: byte_offset,
              native_code: native_code,
              message: "unexpected end of JSON input"
            }} = SimdJson.open("[1,")

    assert is_integer(byte_offset) or is_nil(byte_offset)
    assert is_integer(native_code) or is_nil(native_code)
    wait_for_quiescence()
  end

  defp wait_for_quiescence(attempts \\ 400)

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

    if OperationCoordinator.snapshot().live_requests == 0 and native.live_operations == 0 and
         native.retained_inputs == 0 and native.queued_operations == 0 and
         native.running_operations == 0 and native.live_documents == 0 and
         native.live_document_controls == 0 and native.dispatcher_queued_cleanup == 0 and
         native.dispatcher_active_cleanup == 0 and native.retained_failed_cleanup == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
