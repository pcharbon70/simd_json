defmodule SimdJson.Native.ProjectionBinaryLifetimeTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ProjectionOperation

  setup do
    wait_for_projection_quiescence()
    baseline = BuildSmoke.execution_snapshot()
    on_exit(fn -> wait_for_projection_quiescence() end)
    %{baseline: baseline}
  end

  # covers: simd_json.projection_execution.binary_temporary_document simd_json.projection_execution.generation_and_resource_retention simd_json.projection_engine.typed_result_slots simd_json.projection_engine.transactional_conversion simd_json.projection_api.output_key_identity
  test "binary projection returns exact independent scalar terms and caller keys", %{
    baseline: baseline
  } do
    parent = self()

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        source =
          IO.iodata_to_binary([
            ~s({"signed":-9223372036854775808,),
            ~s("unsigned":18446744073709551615,),
            ~s("float":1.5,"truth":true,"falsehood":false,),
            ~S("nothing":null,"text":"edge\u0000雪"})
          ])

        projection = [
          {:signed, ["signed"]},
          {"signed-copy", ["signed"]},
          {<<255>>, ["unsigned"]},
          {:float, ["float"]},
          {true, ["truth"]},
          {:falsehood, ["falsehood"]},
          {nil, ["nothing"]},
          {"text", ["text"]}
        ]

        send(parent, {:scalar_result, ProjectionOperation.select_for_test(source, projection)})
      end)

    assert_receive {:scalar_result, {:ok, result}}, 2_000
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 2_000

    assert result == %{
             :signed => -9_223_372_036_854_775_808,
             "signed-copy" => -9_223_372_036_854_775_808,
             <<255>> => 18_446_744_073_709_551_615,
             :float => 1.5,
             true => true,
             :falsehood => false,
             nil => nil,
             "text" => <<"edge", 0, "雪">>
           }

    memory_churn = for index <- 1..2_000, do: :binary.copy(<<rem(index, 251)>>, 64)
    :erlang.garbage_collect(self())
    assert length(memory_churn) == 2_000
    assert result["text"] == <<"edge", 0, "雪">>
    assert result[<<255>>] == 18_446_744_073_709_551_615

    wait_for_projection_quiescence()
    after_snapshot = BuildSmoke.execution_snapshot()
    assert_projection_baseline(after_snapshot, baseline)
  end

  # covers: simd_json.projection_execution.binary_temporary_document simd_json.projection_engine.complete_source_validation simd_json.projection_engine.transactional_conversion
  test "malformed, missing, type, and range failures return no partial map" do
    cases = [
      {~s({"selected":1,"bad":[1,]}), [{:selected, ["selected"]}], :invalid_json, nil},
      {~s({"selected":1}), [{:selected, ["selected"]}, {:missing, ["missing"]}], :no_such_field,
       ["missing"]},
      {~s({"value":{}}), [{:value, ["value"]}], :incorrect_type, ["value"]},
      {~s({"value":18446744073709551616}), [{:value, ["value"]}], :number_out_of_range, ["value"]}
    ]

    for {source, projection, reason, path} <- cases do
      assert {:error, %Error{reason: ^reason, path: ^path}} =
               isolated_projection(source, projection)
    end

    wait_for_projection_quiescence()
  end

  # covers: simd_json.projection_engine.transactional_conversion simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_execution.native_memory_baseline
  test "every deterministic worker and conversion checkpoint discards the whole result", %{
    baseline: baseline
  } do
    source = ~s({"first":1,"second":"two","third":true})

    projection = [
      {:first, ["first"]},
      {:second, ["second"]},
      {:third, ["third"]}
    ]

    for successful_checkpoints <- 0..8 do
      assert {:error, %Error{reason: :out_of_memory, path: nil}} =
               isolated_projection(source, projection, failure_after: successful_checkpoints)
    end

    assert {:ok, %{first: 1, second: "two", third: true}} =
             isolated_projection(source, projection, failure_after: 9)

    wait_for_projection_quiescence()
    assert_projection_baseline(BuildSmoke.execution_snapshot(), baseline)
  end

  # covers: simd_json.projection_execution.binary_temporary_document simd_json.projection_execution.native_memory_baseline simd_json.projection_engine.internal_phase_timing simd_json.projection_execution.cancellation_boundaries
  test "one worker owns the temporary graph, plan, slots, environment, and redacted diagnostics",
       %{
         baseline: baseline
       } do
    parent = self()

    entries = for index <- 0..127, do: ~s("key-#{index}":#{index})
    source = "{" <> Enum.join(entries, ",") <> "}"
    projection = for index <- 127..0//-1, do: {"out-#{index}", ["key-#{index}"]}

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        result =
          ProjectionOperation.select_for_test(source, projection,
            pause: {:before_delivery, parent},
            diagnostics: true
          )

        send(parent, {:diagnostic_result, result})
      end)

    assert_receive {
                     :simd_json_native_boundary,
                     request_ref,
                     :projection,
                     _generation,
                     :before_delivery
                   },
                   2_000

    active = BuildSmoke.execution_snapshot()
    assert active.live_projection_operations == baseline.live_projection_operations + 1
    assert active.retained_projection_binaries == baseline.retained_projection_binaries + 1
    assert active.live_projection_environments == baseline.live_projection_environments + 1
    assert active.live_projection_plans == baseline.live_projection_plans + 1
    assert active.live_projection_slots == baseline.live_projection_slots + 128

    assert active.live_projection_temporary_document_graphs ==
             baseline.live_projection_temporary_document_graphs + 1

    assert :ok = OperationCoordinator.release_pause(request_ref)

    assert_receive {:diagnostic_result, {:ok, %{result: result, diagnostics: diagnostics}}},
                   2_000

    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 2_000
    assert map_size(result) == 128
    assert result["out-0"] == 0
    assert result["out-127"] == 127

    assert Map.keys(diagnostics) |> Enum.sort() ==
             [
               :boundary_count,
               :compilation_nanoseconds,
               :term_construction_nanoseconds,
               :traversal_nanoseconds,
               :worker_context
             ]

    assert diagnostics.worker_context == :threaded
    assert diagnostics.boundary_count >= 6

    for field <- [
          :compilation_nanoseconds,
          :traversal_nanoseconds,
          :term_construction_nanoseconds
        ] do
      assert is_integer(diagnostics[field]) and diagnostics[field] >= 0
    end

    wait_for_projection_quiescence()
    assert_projection_baseline(BuildSmoke.execution_snapshot(), baseline)
  end

  defp isolated_projection(source, projection, options \\ []) do
    parent = self()
    ref = make_ref()

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        send(
          parent,
          {ref, ProjectionOperation.select_for_test(source, projection, options)}
        )
      end)

    result =
      receive do
        {^ref, value} -> value
      after
        2_000 -> flunk("isolated projection did not return")
      end

    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 2_000
    result
  end

  defp assert_projection_baseline(snapshot, baseline) do
    for field <- [
          :live_projection_operations,
          :retained_projection_binaries,
          :retained_projection_documents,
          :live_projection_environments,
          :live_projection_plans,
          :live_projection_slots,
          :live_projection_temporary_document_graphs
        ] do
      assert Map.fetch!(snapshot, field) == Map.fetch!(baseline, field),
             "#{field} did not return to its baseline"
    end
  end

  defp wait_for_projection_quiescence(attempts \\ 400)

  defp wait_for_projection_quiescence(0) do
    flunk(
      "binary projection did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
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
         snapshot.retained_projection_documents == 0 and
         snapshot.live_projection_temporary_document_graphs == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_projection_quiescence(attempts - 1)
    end
  end
end
