defmodule SimdJson.Native.StreamDocumentLifecycleTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke

  setup do
    on_exit(fn ->
      :erlang.garbage_collect(self())

      if coordinator = Process.whereis(SimdJson.Native.OperationCoordinator) do
        :erlang.garbage_collect(coordinator)
      end

      Process.sleep(20)
    end)
  end

  # covers: simd_json.stream_execution.exclusive_document_cursor simd_json.stream_execution.document_consumption simd_json.stream_execution.owner_first_admission
  test "rejected stream setup rolls back but cursor access consumes the shared document cursor" do
    {:ok, retryable} = SimdJson.open(~s({"rows": []}))
    assert BuildSmoke.document_projection_owner_state(retryable.__resource__) == :fresh
    assert BuildSmoke.document_stream_reservation_probe(retryable.__resource__, false) == :fresh
    assert BuildSmoke.document_projection_owner_state(retryable.__resource__) == :fresh
    assert SimdJson.close(retryable) == :ok

    {:ok, committed} = SimdJson.open(~s({"rows": []}))
    assert BuildSmoke.document_stream_reservation_probe(committed.__resource__, true) == :consumed
    assert BuildSmoke.document_projection_owner_state(committed.__resource__) == :consumed

    assert {:error, %SimdJson.Error{reason: :cursor_consumed}} =
             SimdJson.select(committed, [{:rows, ["rows"]}])

    assert SimdJson.close(committed) == :ok
  end

  test "non-owner stream reservation reveals no lifecycle or cursor state" do
    {:ok, document} = SimdJson.open(~s({"rows": []}))

    task =
      Task.async(fn ->
        BuildSmoke.document_stream_reservation_probe(document.__resource__, true)
      end)

    assert Task.await(task) == :not_owner
    assert BuildSmoke.document_projection_owner_state(document.__resource__) == :fresh
    assert SimdJson.close(document) == :ok
  end
end
