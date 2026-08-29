defmodule SimdJson.ProjectionValidationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Error
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation
  alias SimdJson.Projection

  @max_array_index 18_446_744_073_709_551_615

  # covers: simd_json.projection_api.projection_grammar simd_json.projection_api.output_key_identity
  test "normalizes output slots, exact keys, u64 indexes, and shared paths deterministically" do
    shared_path = ["customer", "id"]

    projection = [
      {:customer_id, shared_path},
      {"same-id", shared_path},
      {"unicode", ["", "café", 0, @max_array_index]},
      {:keyword_style, ["ready"]}
    ]

    assert {:ok, normalized} = Projection.validate(projection)

    assert Projection.snapshot_for_test(normalized) == %{
             entries: [
               {0, :customer_id, 0},
               {1, "same-id", 0},
               {2, "unicode", 1},
               {3, :keyword_style, 2}
             ],
             paths: [
               {0, shared_path},
               {1, ["", "café", 0, @max_array_index]},
               {2, ["ready"]}
             ]
           }

    assert {:ok, ^normalized} = Projection.validate(projection)

    for source <- [~s({"a":1,"b":2}), ~s({"b":2,"a":1}), "not JSON"] do
      assert {:ok, ^normalized} = Projection.preflight_for_test(source, projection)
    end
  end

  # covers: simd_json.projection_api.projection_grammar simd_json.projection_api.complete_preflight_validation simd_json.projection_api.invalid_projection
  test "rejects every invalid outer collection and output key with one stable error" do
    invalid_projections = [
      [],
      %{},
      {},
      {:not, :a_list},
      [{:missing_path}],
      [{:too, :many, :values}],
      [:not_a_tuple],
      [{0, ["path"]}],
      [{1.0, ["path"]}],
      [{{:tuple}, ["path"]}],
      [{["list"], ["path"]}],
      [{%{}, ["path"]}],
      [{:duplicate, ["first"]}, {:duplicate, ["second"]}],
      [{"duplicate", ["first"]}, {"duplicate", ["second"]}],
      [{:valid, ["path"]} | :improper]
    ]

    for projection <- invalid_projections do
      assert_invalid_projection(projection)
    end
  end

  # covers: simd_json.projection_api.projection_grammar simd_json.projection_api.complete_preflight_validation simd_json.projection_api.invalid_projection
  test "rejects empty, improper, non-UTF-8, and out-of-domain path segments" do
    invalid_paths = [
      [],
      ["valid" | :improper],
      [<<255>>],
      [<<195>>],
      [-1],
      [@max_array_index + 1],
      [1.0],
      [:field],
      [{:field}],
      [%{}],
      [["nested"]],
      [self()],
      [make_ref()]
    ]

    for path <- invalid_paths do
      assert_invalid_projection([{:value, path}])
    end

    late_failure =
      for index <- 0..255 do
        {"valid-#{index}", ["root", index]}
      end

    assert_invalid_projection(late_failure ++ [{"late-invalid", ["root", :invalid]}])
  end

  # covers: simd_json.projection_api.output_key_identity
  test "validating caller binaries never grows the atom table" do
    corpus =
      for index <- 0..1_999 do
        {"output-#{index}", ["object-#{index}", index]}
      end

    assert {:ok, _warm} = Projection.validate([{"warm-output", ["warm-path"]}])
    :erlang.garbage_collect(self())
    before = :erlang.system_info(:atom_count)

    assert {:ok, normalized} = Projection.validate(corpus)
    assert length(Projection.snapshot_for_test(normalized).entries) == 2_000
    assert :erlang.system_info(:atom_count) == before
  end

  # covers: simd_json.projection_api.complete_preflight_validation simd_json.projection_api.invalid_projection simd_json.projection_execution.preadmission_nonconsumption
  test "invalid document preflight creates no native admission or lifecycle change" do
    assert {:ok, %Document{} = document} = SimdJson.open(~s({"kept":"fresh"}))
    %Document{__resource__: resource} = document
    wait_for_operation_quiescence()

    native_before = BuildSmoke.execution_snapshot()
    admissions_before = ThreadedOperation.admission_snapshot_for_test()
    generation = BuildSmoke.execution_generation()
    assert BuildSmoke.document_lifecycle(resource) == :open
    assert BuildSmoke.document_owner_state(resource) == :open

    invalid_projections = [
      [],
      [{:valid, ["kept"]}, {:late, ["kept", :invalid]}],
      [{:duplicate, ["kept"]}, {:duplicate, ["other"]}]
    ]

    for projection <- invalid_projections do
      assert {:error,
              %Error{
                reason: :invalid_projection,
                message: "invalid projection",
                byte_offset: nil,
                native_code: nil
              }} = Projection.preflight_for_test(document, projection)
    end

    assert {:ok, _normalized} =
             Projection.preflight_for_test(document, [{:kept, ["kept"]}])

    assert ThreadedOperation.admission_snapshot_for_test() == admissions_before
    assert BuildSmoke.execution_snapshot() == native_before
    assert BuildSmoke.execution_generation() == generation
    assert BuildSmoke.document_lifecycle(resource) == :open
    assert BuildSmoke.document_owner_state(resource) == :open

    assert :ok = SimdJson.close(document)
  end

  defp assert_invalid_projection(projection) do
    assert {:error,
            %Error{
              reason: :invalid_projection,
              message: "invalid projection",
              byte_offset: nil,
              native_code: nil
            }} = Projection.validate(projection)
  end

  defp wait_for_operation_quiescence(attempts \\ 400)

  defp wait_for_operation_quiescence(0) do
    flunk(
      "native operation did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_operation_quiescence(attempts) do
    :erlang.garbage_collect(self())
    :erlang.garbage_collect(Process.whereis(OperationCoordinator))
    snapshot = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and snapshot.live_operations == 0 and
         snapshot.retained_inputs == 0 and snapshot.queued_operations == 0 and
         snapshot.running_operations == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_operation_quiescence(attempts - 1)
    end
  end
end
