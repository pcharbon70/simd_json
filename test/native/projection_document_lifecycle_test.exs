defmodule SimdJson.Native.ProjectionDocumentLifecycleTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ProjectionOperation
  alias SimdJson.Projection

  setup do
    wait_for_native_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      OperationCoordinator.set_submission_rejection_for_test(:projection, false)
      OperationCoordinator.set_submission_rejection_for_test(:document_cleanup, false)
      wait_for_native_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.projection_execution.owner_first_admission simd_json.projection_execution.preadmission_nonconsumption simd_json.projection_execution.close_interlock simd_json.document_resource.idempotent_close
  test "owner-first admission also holds while a fresh document is closing or closed" do
    parent = self()
    {owner_pid, owner_monitor} = spawn_monitor(fn -> document_owner(parent) end)
    assert_receive {:owned_document, ^owner_pid, %Document{} = document}, 2_000
    %Document{__resource__: resource} = document
    projection = [{:id, ["account", "id"]}]

    prepare_ref = make_ref()
    send(owner_pid, {:prepare_close, prepare_ref})
    assert_receive {:owner_prepared_close, ^prepare_ref, :closing}, 2_000

    request_owner_state(owner_pid, :closing)
    assert BuildSmoke.document_lifecycle(resource) == :closing

    assert {:error, %Error{reason: :not_owner}} =
             ProjectionOperation.select_for_test(document, projection)

    retry_ref = make_ref()
    send(owner_pid, {:close_once, retry_ref})
    assert_receive {:owner_close_once, ^retry_ref, :ok}, 2_000
    request_owner_state(owner_pid, :closed)

    assert {:error, %Error{reason: :not_owner}} =
             ProjectionOperation.select_for_test(document, projection)

    owner_select_ref = make_ref()
    send(owner_pid, {:select, owner_select_ref, projection, []})
    assert_receive {:owner_result, ^owner_select_ref, {:error, %Error{reason: :closed}}}, 2_000

    send(owner_pid, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner_pid, :normal}, 2_000
  end

  # covers: simd_json.projection_execution.owner_first_admission simd_json.projection_execution.exclusive_document_selection simd_json.projection_execution.committed_consumption simd_json.projection_execution.generation_and_resource_retention
  test "owner-first reservation exposes no fresh, selecting, or consumed state to another process" do
    parent = self()
    owner = spawn_monitor(fn -> document_owner(parent) end)
    {owner_pid, owner_monitor} = owner

    assert_receive {:owned_document, ^owner_pid, %Document{} = document}, 2_000
    %Document{__resource__: resource} = document
    projection = [{:id, ["account", "id"]}]
    {:ok, normalized} = Projection.validate(projection)
    request_owner_state(owner_pid, :fresh)

    assert {:error, %Error{reason: :not_owner}} =
             ProjectionOperation.select_for_test(document, projection)

    request_owner_state(owner_pid, :fresh)
    select_ref = make_ref()

    send(
      owner_pid,
      {:select, select_ref, projection, [pause: {:before_cursor_access, parent}]}
    )

    assert_receive {
                     :simd_json_native_boundary,
                     request_ref,
                     :projection,
                     generation,
                     :before_cursor_access
                   },
                   2_000

    assert BuildSmoke.document_projection_owner_state(resource) == :not_owner

    assert %{status: :cursor_consumed, operation: nil} =
             BuildSmoke.projection_operation_admit(
               resource,
               normalized,
               owner_pid,
               :document,
               generation
             )

    assert generation == BuildSmoke.execution_generation()

    assert {:error, %Error{reason: :not_owner}} =
             ProjectionOperation.select_for_test(document, projection)

    assert :ok = OperationCoordinator.release_pause(request_ref)
    assert_receive {:owner_result, ^select_ref, {:ok, %{id: 7}}}, 2_000

    request_owner_state(owner_pid, :consumed)

    assert {:error, %Error{reason: :not_owner}} =
             ProjectionOperation.select_for_test(document, projection)

    second_ref = make_ref()
    send(owner_pid, {:select, second_ref, projection, []})

    assert_receive {:owner_result, ^second_ref, {:error, %Error{reason: :cursor_consumed}}},
                   2_000

    send(owner_pid, {:close, self()})
    assert_receive {:owner_close, :ok, :ok}, 2_000
    assert BuildSmoke.document_lifecycle(resource) == :closed
    assert BuildSmoke.document_projection_owner_state(resource) == :not_owner

    send(owner_pid, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner_pid, :normal}, 2_000
  end

  # covers: simd_json.projection_execution.preadmission_nonconsumption simd_json.projection_execution.exclusive_document_selection simd_json.native_execution.no_fallback
  test "invalid preflight and rejected submission leave a fresh document retryable", %{
    baseline: baseline
  } do
    assert {:ok, %Document{__resource__: resource} = document} =
             SimdJson.open(~s({"value":12}))

    wait_for_projection_quiescence()
    before = BuildSmoke.execution_snapshot()
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh

    assert {:error, %Error{reason: :invalid_projection}} =
             ProjectionOperation.select_for_test(document, [])

    assert BuildSmoke.document_projection_owner_state(resource) == :fresh
    assert BuildSmoke.execution_snapshot() == before

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, true)

    assert {:error, %Error{reason: :native_failure}} =
             ProjectionOperation.select_for_test(document, [{:value, ["value"]}])

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    wait_for_projection_quiescence()

    assert BuildSmoke.document_projection_owner_state(resource) == :fresh
    rejected = BuildSmoke.execution_snapshot()
    assert rejected.projection_worker_entries == before.projection_worker_entries

    assert {:ok, %{value: 12}} =
             ProjectionOperation.select_for_test(document, [{:value, ["value"]}])

    assert BuildSmoke.document_projection_owner_state(resource) == :consumed
    assert :ok = SimdJson.close(document)
    assert :ok = SimdJson.close(document)
    wait_for_projection_quiescence()

    after_snapshot = BuildSmoke.execution_snapshot()
    assert_projection_baseline(after_snapshot, baseline)
  end

  # covers: simd_json.projection_execution.committed_consumption simd_json.projection_execution.preadmission_nonconsumption simd_json.projection_engine.transactional_conversion
  test "every path, type, and conversion failure after cursor access consumes the document" do
    cases = [
      {~s({"found":1}), [{:missing, ["missing"]}], :no_such_field, ["missing"], []},
      {~s({"items":[1]}), [{:item, ["items", 2]}], :index_out_of_bounds, ["items", 2], []},
      {~s({"value":{}}), [{:value, ["value"]}], :incorrect_type, ["value"], []},
      {~s({"value":1}), [{:value, ["value"]}], :out_of_memory, nil, [failure_after: 2]}
    ]

    for {source, projection, reason, path, options} <- cases do
      assert {:ok, %Document{__resource__: resource} = document} = SimdJson.open(source)
      assert BuildSmoke.document_projection_owner_state(resource) == :fresh

      assert {:error, %Error{reason: ^reason, path: ^path}} =
               ProjectionOperation.select_for_test(document, projection, options)

      assert BuildSmoke.document_projection_owner_state(resource) == :consumed

      assert {:error, %Error{reason: :cursor_consumed}} =
               ProjectionOperation.select_for_test(document, projection)

      assert :ok = SimdJson.close(document)
      assert :ok = SimdJson.close(document)
    end
  end

  # covers: simd_json.projection_execution.close_interlock simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.committed_consumption simd_json.document_resource.reverse_destruction
  test "close cancels traversal, waits for reservation release, and destroys once", %{
    baseline: baseline
  } do
    parent = self()
    {owner_pid, owner_monitor} = spawn_monitor(fn -> document_owner(parent, large_document()) end)

    assert_receive {:owned_document, ^owner_pid, %Document{} = document}, 2_000
    %Document{__resource__: resource} = document
    projection = [{:last, ["items", 4_095, "value"]}]
    select_ref = make_ref()

    send(
      owner_pid,
      {:select, select_ref, projection, [pause: {:during_traversal, parent}]}
    )

    assert_receive {
                     :simd_json_native_boundary,
                     _request_ref,
                     :projection,
                     _generation,
                     :during_traversal
                   },
                   2_000

    cleanup = Task.async(fn -> SimdJson.Native.ThreadedOperation.cleanup(resource) end)
    assert_receive {:owner_result, ^select_ref, {:error, %Error{reason: :cancelled}}}, 2_000
    assert Task.await(cleanup, 2_000) == :ok
    assert BuildSmoke.document_lifecycle(resource) == :closed

    send(owner_pid, {:state, self()})
    assert_receive {:owner_state, :consumed}, 2_000
    send(owner_pid, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner_pid, :normal}, 2_000

    wait_for_projection_quiescence()
    after_snapshot = BuildSmoke.execution_snapshot()
    assert_projection_baseline(after_snapshot, baseline)

    assert after_snapshot.completed_document_cleanup ==
             baseline.completed_document_cleanup + 1
  end

  defp document_owner(parent, source \\ ~s({"account":{"id":7}})) do
    {:ok, document} = SimdJson.open(source)
    send(parent, {:owned_document, self(), document})
    document_owner_loop(document, parent)
  end

  defp document_owner_loop(%Document{__resource__: resource} = document, parent) do
    receive do
      {:state, reply_to} ->
        send(reply_to, {:owner_state, BuildSmoke.document_projection_owner_state(resource)})
        document_owner_loop(document, parent)

      {:select, ref, projection, options} ->
        result = ProjectionOperation.select_for_test(document, projection, options)
        send(parent, {:owner_result, ref, result})
        document_owner_loop(document, parent)

      {:close, reply_to} ->
        first = SimdJson.close(document)
        second = SimdJson.close(document)
        send(reply_to, {:owner_close, first, second})
        document_owner_loop(document, parent)

      {:close_once, ref} ->
        send(parent, {:owner_close_once, ref, SimdJson.close(document)})
        document_owner_loop(document, parent)

      {:prepare_close, ref} ->
        send(parent, {:owner_prepared_close, ref, BuildSmoke.document_prepare_cleanup(resource)})
        document_owner_loop(document, parent)

      :stop ->
        :ok
    end
  end

  defp request_owner_state(owner, expected) do
    send(owner, {:state, self()})
    assert_receive {:owner_state, ^expected}, 2_000
  end

  defp large_document do
    items =
      0..4_095
      |> Enum.map_join(",", fn index -> ~s({"value":#{index},"padding":"0123456789"}) end)

    ~s({"items":[#{items}]})
  end

  defp assert_projection_baseline(snapshot, baseline) do
    for field <- [
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
    flunk("projection did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}")
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

  defp wait_for_native_quiescence(attempts \\ 400)

  defp wait_for_native_quiescence(0) do
    flunk(
      "native state did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_native_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.running_operations == 0 and snapshot.queued_operations == 0 and
         snapshot.live_documents == 0 and snapshot.live_document_controls == 0 and
         snapshot.dispatcher_queued_cleanup == 0 and snapshot.dispatcher_active_cleanup == 0 and
         snapshot.retained_failed_cleanup == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_native_quiescence(attempts - 1)
    end
  end
end
