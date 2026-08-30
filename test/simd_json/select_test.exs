defmodule SimdJson.SelectTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ProjectionOperation
  alias SimdJson.Native.ThreadedOperation

  @max_u64 18_446_744_073_709_551_615
  @idle_gauges [
    :live_operations,
    :retained_inputs,
    :queued_operations,
    :running_operations,
    :live_projection_operations,
    :retained_projection_binaries,
    :retained_projection_documents,
    :live_projection_environments,
    :live_projection_plans,
    :live_projection_slots,
    :live_projection_temporary_document_graphs
  ]

  setup do
    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    wait_for_quiescence()
    baseline = BuildSmoke.execution_snapshot()

    on_exit(fn ->
      :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
      wait_for_quiescence()
    end)

    %{baseline: baseline}
  end

  # covers: simd_json.projection_api.select_contract simd_json.projection_api.output_key_identity simd_json.projection_api.scalar_results simd_json.projection_api.fresh_string_results simd_json.projection_api.binary_multi_select simd_json.projection_api.all_scalar_types simd_json.projection_engine.declaration_order_independence simd_json.projection_engine.duplicate_json_key_policy simd_json.projection_execution.binary_operation_lifetime
  test "selects every scalar under exact keys in source order independently of declaration order",
       %{baseline: baseline} do
    source =
      IO.iodata_to_binary([
        ~s({"duplicate":"first","duplicate":"second",),
        ~s("nested":{"雪":[{"escaped key":"line\\n雪"}]},),
        ~s("signed":-9223372036854775808,),
        ~s("unsigned":18446744073709551615,),
        ~s("float":1.5,"truth":true,"falsehood":false,"nothing":null,),
        ~s("discard":{"large":"#{String.duplicate("x", 65_536)}"}})
      ])

    projection = [
      {"nothing", ["nothing"]},
      {:falsehood, ["falsehood"]},
      {true, ["truth"]},
      {:float, ["float"]},
      {<<255>>, ["unsigned"]},
      {:signed_copy, ["signed"]},
      {:signed, ["signed"]},
      {"escaped", ["nested", "雪", 0, "escaped key"]},
      {:duplicate, ["duplicate"]}
    ]

    assert {:ok, result} = SimdJson.select(source, projection)

    assert result == %{
             "nothing" => nil,
             :falsehood => false,
             true => true,
             :float => 1.5,
             <<255>> => @max_u64,
             :signed_copy => -9_223_372_036_854_775_808,
             :signed => -9_223_372_036_854_775_808,
             "escaped" => "line\n雪",
             :duplicate => "first"
           }

    assert {:ok, ^result} = SimdJson.select(source, projection)

    assert :binary.referenced_byte_size(result["escaped"]) < byte_size(source)
    assert :binary.referenced_byte_size(result["escaped"]) <= 128
    source = nil
    :erlang.garbage_collect(self())
    assert source == nil
    assert result["escaped"] == "line\n雪"

    wait_for_quiescence()
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.projection_api.select_contract simd_json.projection_api.document_select simd_json.projection_api.fresh_string_results simd_json.projection_execution.document_one_shot
  test "document selection returns independent terms once and close stays idempotent" do
    assert {:ok, %Document{} = document} =
             SimdJson.open(~s({"account":{"name":"owned 雪","id":17}}))

    projection = [{"name", ["account", "name"]}, {:id, ["account", "id"]}]
    assert {:ok, %{"name" => selected, id: 17}} = SimdJson.select(document, projection)
    assert :binary.referenced_byte_size(selected) <= 128

    assert {:error, %Error{reason: :cursor_consumed, path: nil}} =
             SimdJson.select(document, projection)

    assert :ok = SimdJson.close(document)
    assert :ok = SimdJson.close(document)
    document = nil
    :erlang.garbage_collect(self())
    assert document == nil
    assert selected == "owned 雪"
  end

  # covers: simd_json.projection_api.source_argument_validation simd_json.projection_api.invalid_source_argument simd_json.projection_execution.preadmission_nonconsumption
  test "invalid and forged sources raise before projection admission", %{baseline: baseline} do
    projection = [{:value, ["value"]}]
    admission_before = ThreadedOperation.admission_snapshot_for_test()

    invalid_sources = [
      nil,
      :json,
      0,
      1.0,
      [],
      ["{}"],
      %{},
      {},
      make_ref(),
      self(),
      fn -> :ok end,
      <<1::1>>,
      %Document{__resource__: make_ref()},
      %Document{__resource__: nil}
    ]

    for source <- invalid_sources do
      assert_raise ArgumentError,
                   "expected JSON input to be a binary or SimdJson.Document",
                   fn -> SimdJson.select(source, projection) end
    end

    operation = ThreadedOperation.admit(<<>>, :threaded_smoke)
    forged = %Document{__resource__: operation.resource}
    before_other_resource = BuildSmoke.execution_snapshot()

    assert_raise ArgumentError,
                 "expected JSON input to be a binary or SimdJson.Document",
                 fn -> SimdJson.select(forged, projection) end

    after_other_resource = BuildSmoke.execution_snapshot()

    assert after_other_resource.projection_worker_entries ==
             before_other_resource.projection_worker_entries

    assert ThreadedOperation.admission_snapshot_for_test().projection ==
             admission_before.projection

    assert BuildSmoke.operation_finish(operation.resource, :discarded)

    operation = forged = nil
    wait_for_quiescence()
    assert operation == nil and forged == nil
    assert_idle(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.projection_api.complete_preflight_validation simd_json.projection_api.invalid_projection simd_json.projection_execution.preadmission_nonconsumption
  test "complete invalid projection preflight neither parses nor consumes" do
    assert {:ok, %Document{__resource__: resource} = document} =
             SimdJson.open(~s({"value":23}))

    wait_for_quiescence()
    admission_before = ThreadedOperation.admission_snapshot_for_test()
    native_before = BuildSmoke.execution_snapshot()

    invalid_projections = [
      [],
      %{},
      [{:value}],
      [{0, ["value"]}],
      [{:value, []}],
      [{:value, ["value" | :improper]}],
      [{:value, [<<255>>]}],
      [{:value, [-1]}],
      [{:value, [@max_u64 + 1]}],
      [{:value, ["value", :unsupported]}],
      [{:duplicate, ["value"]}, {:duplicate, ["other"]}],
      [{:value, ["value"]} | :improper]
    ]

    for invalid <- invalid_projections, source <- [document, "not JSON"] do
      assert {:error,
              %Error{
                reason: :invalid_projection,
                byte_offset: nil,
                native_code: nil,
                path: nil
              }} = SimdJson.select(source, invalid)
    end

    assert {:error, %Error{reason: :invalid_projection}} =
             SimdJson.select(:invalid_source, List.last(invalid_projections))

    assert ThreadedOperation.admission_snapshot_for_test() == admission_before
    assert BuildSmoke.execution_snapshot() == native_before
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh

    assert {:ok, %{value: 23}} = SimdJson.select(document, value: ["value"])
    assert BuildSmoke.document_projection_owner_state(resource) == :consumed
    assert :ok = SimdJson.close(document)
  end

  # covers: simd_json.projection_api.projection_error_reasons simd_json.projection_api.error_path simd_json.projection_api.atomic_result simd_json.projection_api.path_failures simd_json.projection_engine.complete_source_validation simd_json.projection_engine.scalar_only_materialization simd_json.projection_engine.transactional_conversion
  test "path, range, container, and complete-source failures are atomic and stable" do
    cases = [
      {~s({"early":1}), [{:early, ["early"]}, {:failure, ["missing"]}], :no_such_field,
       ["missing"]},
      {~s({"early":1,"items":[0]}), [{:early, ["early"]}, {:failure, ["items", 4]}],
       :index_out_of_bounds, ["items", 4]},
      {~s({"early":1,"value":false}), [{:early, ["early"]}, {:failure, ["value", "child"]}],
       :incorrect_type, ["value", "child"]},
      {~s({"early":1,"value":{}}), [{:early, ["early"]}, {:failure, ["value"]}], :incorrect_type,
       ["value"]},
      {~s({"early":1,"value":[]}), [{:early, ["early"]}, {:failure, ["value"]}], :incorrect_type,
       ["value"]},
      {~s({"early":1,"value":18446744073709551616}), [{:early, ["early"]}, {:failure, ["value"]}],
       :number_out_of_range, ["value"]},
      {~s({"early":1,"unselected":[0,]}), [{:early, ["early"]}], [:invalid_json, :unexpected_eof],
       nil},
      {~s({"early":1} trailing), [{:early, ["early"]}], [:invalid_json, :unexpected_eof], nil},
      {~s({"early":1), [{:early, ["early"]}], :unexpected_eof, nil},
      {<<123, 34, 255, 34, 58, 49, 125>>, [{:value, ["value"]}], :invalid_utf8, nil}
    ]

    for {source, projection, reason, path} <- cases do
      assert {:error, %Error{path: ^path} = error} = SimdJson.select(source, projection)
      assert error.reason in List.wrap(reason)

      if error.byte_offset != nil do
        assert error.byte_offset in 0..byte_size(source)
      end
    end
  end

  # covers: simd_json.projection_api.projection_error_reasons simd_json.projection_api.error_path simd_json.document_api.error_redaction
  test "the sole translator validates paths, offsets, native codes, and unknown statuses" do
    secret = "caller-secret-path-5521"
    projection = [{:first, ["first"]}, {:secret, [secret, 0]}]

    assert %Error{
             reason: :no_such_field,
             path: [^secret, 0],
             byte_offset: 4,
             native_code: 17
           } =
             ProjectionOperation.translate_error_for_test(
               %{reason: :missing_field, output_slot: 1, byte_offset: 4, native_code: 17},
               projection,
               4
             )

    malformed_metadata = [
      {%{reason: :missing_field, output_slot: -1}, :no_such_field},
      {%{reason: :missing_field, output_slot: 99}, :no_such_field},
      {%{reason: :missing_field, output_slot: "1"}, :no_such_field},
      {%{reason: :future_native_status, output_slot: 1, byte_offset: 99}, :native_failure},
      {%{reason: self(), output_slot: 1, native_code: @max_u64}, :native_failure}
    ]

    for {native, reason} <- malformed_metadata do
      error = ProjectionOperation.translate_error_for_test(native, projection, 4)
      assert error.reason == reason
      assert error.path == nil
      assert error.byte_offset == nil
      assert error.native_code == nil
    end

    unknown =
      ProjectionOperation.translate_error_for_test(
        %{reason: :future_native_status, output_slot: 1, byte_offset: 3, native_code: -7},
        projection,
        4
      )

    assert %Error{reason: :native_failure, path: nil, byte_offset: 3, native_code: -7} = unknown

    log =
      capture_log(fn ->
        require Logger
        Logger.error("projection failed: #{inspect(unknown)}")
      end)

    for rendered <- [unknown.message, inspect(unknown), log] do
      refute rendered =~ secret
      refute rendered =~ "0x"
      refute rendered =~ "C++"
    end
  end

  # covers: simd_json.projection_api.output_key_identity simd_json.projection_api.atom_and_surface_safety
  test "public selection never atomizes output or JSON keys" do
    source_entries = for index <- 0..999, do: ~s("json-key-#{index}":#{index})
    source = "{" <> Enum.join(source_entries, ",") <> "}"
    projection = for index <- 0..999, do: {"result-key-#{index}", ["json-key-#{index}"]}

    assert {:ok, _warmup} = SimdJson.select(~s({"warm":1}), [{"warm-result", ["warm"]}])
    :erlang.garbage_collect(self())
    before = :erlang.system_info(:atom_count)

    assert {:ok, result} = SimdJson.select(source, projection)
    assert map_size(result) == 1_000
    assert result["result-key-0"] == 0
    assert result["result-key-999"] == 999
    assert :erlang.system_info(:atom_count) == before
  end

  # covers: simd_json.projection_execution.submission_rejection_retry simd_json.projection_execution.preadmission_nonconsumption simd_json.native_execution.no_fallback
  test "public submission rejection returns stable failure and leaves a document retryable" do
    assert {:ok, %Document{__resource__: resource} = document} =
             SimdJson.open(~s({"value":31}))

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, true)
    before = BuildSmoke.execution_snapshot()

    assert {:error, %Error{reason: :native_failure, path: nil}} =
             SimdJson.select(document, value: ["value"])

    :ok = OperationCoordinator.set_submission_rejection_for_test(:projection, false)
    wait_for_quiescence()
    rejected = BuildSmoke.execution_snapshot()
    assert rejected.projection_worker_entries == before.projection_worker_entries
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh

    assert {:ok, %{value: 31}} = SimdJson.select(document, value: ["value"])
    assert BuildSmoke.document_projection_owner_state(resource) == :consumed
    assert :ok = SimdJson.close(document)
  end

  # covers: simd_json.projection_execution.owner_first_admission simd_json.projection_execution.preadmission_nonconsumption simd_json.projection_execution.document_one_shot simd_json.projection_execution.non_owner_and_close_race simd_json.projection_api.document_select
  test "public document selection checks owner before fresh, consumed, and closed state" do
    parent = self()

    {owner, monitor} = spawn_monitor(fn -> public_document_owner(parent) end)

    assert_receive {:public_document, ^owner, %Document{} = document}, 2_000
    projection = [{:value, ["value"]}]
    before = ThreadedOperation.admission_snapshot_for_test()

    assert {:error, %Error{reason: :not_owner, path: nil}} =
             SimdJson.select(document, projection)

    assert ThreadedOperation.admission_snapshot_for_test().projection == before.projection

    select_ref = make_ref()
    send(owner, {:select, select_ref, projection})
    assert_receive {:public_owner_result, ^select_ref, {:ok, %{value: 47}}}, 2_000

    assert {:error, %Error{reason: :not_owner, path: nil}} =
             SimdJson.select(document, projection)

    closed_ref = make_ref()
    send(owner, {:close_and_select, closed_ref, projection})

    assert_receive {:public_owner_closed, ^closed_ref, :ok,
                    {:error, %Error{reason: :closed, path: nil}}},
                   2_000

    assert {:error, %Error{reason: :not_owner, path: nil}} =
             SimdJson.select(document, projection)

    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}, 2_000
  end

  defp assert_idle(snapshot, baseline) do
    for field <- @idle_gauges do
      assert Map.fetch!(snapshot, field) == Map.fetch!(baseline, field),
             "#{field} did not return to its baseline"
    end
  end

  defp public_document_owner(parent) do
    {:ok, document} = SimdJson.open(~s({"value":47}))
    send(parent, {:public_document, self(), document})
    public_document_owner_loop(document, parent)
  end

  defp public_document_owner_loop(document, parent) do
    receive do
      {:select, ref, projection} ->
        send(parent, {:public_owner_result, ref, SimdJson.select(document, projection)})
        public_document_owner_loop(document, parent)

      {:close_and_select, ref, projection} ->
        close_result = SimdJson.close(document)
        select_result = SimdJson.select(document, projection)
        send(parent, {:public_owner_closed, ref, close_result, select_result})
        public_document_owner_loop(document, parent)

      :stop ->
        :ok
    end
  end

  defp wait_for_quiescence(attempts \\ 500)

  defp wait_for_quiescence(0) do
    flunk(
      "projection did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and
         Enum.all?(@idle_gauges, &(Map.fetch!(snapshot, &1) == 0)) do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
