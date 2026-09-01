defmodule SimdJson.StreamOptionsTest do
  use ExUnit.Case, async: false

  alias SimdJson.Document
  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.OperationCoordinator
  alias SimdJson.Native.ThreadedOperation
  alias SimdJson.StreamOptions

  @max_u64 18_446_744_073_709_551_615
  @fields [
    {:id, ["customer", "id"]},
    {"same-id", ["customer", "id"]},
    {"unicode", ["雪", 0, @max_u64]}
  ]

  setup do
    wait_for_quiescence()
    :ok
  end

  # covers: simd_json.streaming_api.target_path simd_json.streaming_api.fields_projection simd_json.streaming_api.public_limits
  test "normalizes root target, fields, defaults, and explicit option identity" do
    normalized = StreamOptions.new("not inspected as JSON", path: [], fields: @fields)

    assert StreamOptions.snapshot_for_test(normalized) == %{
             source_kind: :binary,
             owner_matches: true,
             target_path: [],
             fields: %{
               entries: [{0, :id, 0}, {1, "same-id", 0}, {2, "unicode", 1}],
               paths: [
                 {0, ["customer", "id"]},
                 {1, ["雪", 0, @max_u64]}
               ]
             },
             batch_size: 1_000,
             max_batch_bytes: 8_388_608,
             explicit_options: [:path, :fields]
           }
  end

  # covers: simd_json.streaming_api.option_grammar simd_json.streaming_api.target_path simd_json.streaming_api.fields_projection simd_json.streaming_api.public_limits
  test "normalization is independent of keyword ordering and preserves explicit limits" do
    source = ~s({"not":"parsed"})

    first =
      StreamOptions.new(source,
        path: ["customers", 0, "orders"],
        fields: @fields,
        batch_size: 10_000,
        max_batch_bytes: 67_108_864
      )

    second =
      StreamOptions.new(source,
        max_batch_bytes: 67_108_864,
        fields: @fields,
        path: ["customers", 0, "orders"],
        batch_size: 10_000
      )

    assert StreamOptions.snapshot_for_test(first) == StreamOptions.snapshot_for_test(second)

    assert %{
             target_path: ["customers", 0, "orders"],
             batch_size: 10_000,
             max_batch_bytes: 67_108_864,
             explicit_options: [:path, :fields, :batch_size, :max_batch_bytes]
           } = StreamOptions.snapshot_for_test(first)
  end

  # covers: simd_json.streaming_api.lazy_construction simd_json.streaming_api.opaque_stream
  test "opaque term captures its immutable owner without exposing sensitive payload" do
    source_secret = "stream-source-secret-7041"
    path_secret = "stream-path-secret-7041"
    key_secret = "stream-output-secret-7041"

    task =
      Task.async(fn ->
        StreamOptions.new(source_secret,
          path: [path_secret],
          fields: [{key_secret, [path_secret]}]
        )
      end)

    normalized = Task.await(task)
    rendered = inspect(normalized)

    refute StreamOptions.snapshot_for_test(normalized).owner_matches
    refute rendered =~ source_secret
    refute rendered =~ path_secret
    refute rendered =~ key_secret
    refute rendered =~ inspect(task.pid)
    assert byte_size(rendered) < 320
  end

  # covers: simd_json.streaming_api.source_argument_validation simd_json.streaming_api.option_grammar simd_json.stream_execution.lazy_setup
  test "rejects invalid sources and closed option collections before admission" do
    options = [path: [], fields: @fields]

    invalid_sources = [
      nil,
      :source,
      1,
      1.0,
      [],
      {},
      %{},
      %Document{__resource__: make_ref()},
      %Document{__resource__: :not_a_reference}
    ]

    invalid_options = [
      nil,
      %{},
      {},
      [],
      [path: []],
      [fields: @fields],
      [path: [], fields: @fields, unknown: true],
      [{:path, []}, {:path, []}, {:fields, @fields}],
      [{:path, []}, {:fields, @fields}, {:fields, @fields}],
      [{:path, []}, {:fields, @fields}, {:batch_size, 1}, {:batch_size, 2}],
      [{:path, []}, {:fields, @fields}, {:max_batch_bytes, 1}, {:max_batch_bytes, 2}],
      [{:path, []}, {:fields, @fields}, :not_a_pair],
      [{:path, []}, {:fields, @fields} | :improper]
    ]

    admissions_before = ThreadedOperation.admission_snapshot_for_test()
    native_before = BuildSmoke.execution_snapshot()
    generation = BuildSmoke.execution_generation()

    assert admissions_before.stream_setup == 0
    assert admissions_before.stream_batch == 0

    for source <- invalid_sources do
      assert_raise ArgumentError,
                   "expected JSON input to be a binary or SimdJson.Document",
                   fn -> StreamOptions.new(source, options) end
    end

    for bad_options <- invalid_options do
      assert_raise ArgumentError, "invalid stream options", fn ->
        StreamOptions.new("not JSON", bad_options)
      end
    end

    assert ThreadedOperation.admission_snapshot_for_test() == admissions_before
    assert BuildSmoke.execution_snapshot() == native_before
    assert BuildSmoke.execution_generation() == generation
  end

  # covers: simd_json.streaming_api.target_path simd_json.streaming_api.fields_projection simd_json.streaming_api.public_limits simd_json.streaming_api.option_grammar
  test "rejects every invalid target, field, and numeric boundary deterministically" do
    invalid_paths = [
      nil,
      %{},
      {},
      "path",
      ["valid" | :improper],
      [<<255>>],
      [-1],
      [@max_u64 + 1],
      [1.0],
      [:atom],
      [["nested"]],
      [%{}],
      ["valid", @max_u64, "late", :invalid]
    ]

    invalid_fields = [
      [],
      %{},
      [{:field, []}],
      [{:field, ["valid"]}, {:late, ["valid", :invalid]}],
      [{:duplicate, ["first"]}, {:duplicate, ["second"]}],
      [{"valid", ["path"]} | :improper]
    ]

    invalid_batch_sizes = [0, -1, 10_001, 1.0, "1", nil, true]
    invalid_max_batch_bytes = [0, -1, 67_108_865, 1.0, "1", nil, true]

    for path <- invalid_paths do
      assert_raise ArgumentError, "invalid stream path", fn ->
        StreamOptions.new("not JSON", path: path, fields: @fields)
      end
    end

    for fields <- invalid_fields do
      assert_raise ArgumentError, "invalid stream fields", fn ->
        StreamOptions.new("not JSON", path: [], fields: fields)
      end
    end

    for batch_size <- invalid_batch_sizes do
      assert_raise ArgumentError, "invalid stream batch_size", fn ->
        StreamOptions.new("not JSON", path: [], fields: @fields, batch_size: batch_size)
      end
    end

    for max_batch_bytes <- invalid_max_batch_bytes do
      assert_raise ArgumentError, "invalid stream max_batch_bytes", fn ->
        StreamOptions.new("not JSON",
          path: [],
          fields: @fields,
          max_batch_bytes: max_batch_bytes
        )
      end
    end
  end

  # covers: simd_json.streaming_api.lazy_construction simd_json.stream_execution.lazy_setup simd_json.stream_execution.owner_first_admission simd_json.stream_execution.document_consumption
  test "valid binary and document construction is parse-free and lifecycle-neutral" do
    assert {:ok, %Document{__resource__: resource} = document} =
             SimdJson.open(~s({"customers":[{"id":1}]}))

    wait_for_quiescence()
    admissions_before = ThreadedOperation.admission_snapshot_for_test()
    native_before = BuildSmoke.execution_snapshot()
    coordinator_before = OperationCoordinator.snapshot()
    generation = BuildSmoke.execution_generation()

    assert admissions_before.stream_setup == 0
    assert admissions_before.stream_batch == 0

    assert BuildSmoke.document_owner_state(resource) == :open
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh

    invalid_json = :binary.copy("not JSON and never parsed", 1_024)

    binary_options =
      StreamOptions.new(invalid_json,
        path: ["customers"],
        fields: [id: ["id"]]
      )

    document_options =
      StreamOptions.new(document,
        path: ["customers"],
        fields: [id: ["id"]]
      )

    assert StreamOptions.snapshot_for_test(binary_options).source_kind == :binary
    assert StreamOptions.snapshot_for_test(document_options).source_kind == :document
    assert ThreadedOperation.admission_snapshot_for_test() == admissions_before
    assert BuildSmoke.execution_snapshot() == native_before
    assert OperationCoordinator.snapshot() == coordinator_before
    assert BuildSmoke.execution_generation() == generation
    assert BuildSmoke.document_owner_state(resource) == :open
    assert BuildSmoke.document_projection_owner_state(resource) == :fresh

    assert :ok = SimdJson.close(document)
  end

  # covers: simd_json.streaming_api.source_argument_validation simd_json.streaming_api.lazy_construction simd_json.streaming_api.owner_bound_reduction
  test "genuine document shape validation defers owner and lifecycle failures" do
    parent = self()

    owner =
      spawn_link(fn ->
        {:ok, document} = SimdJson.open(~s({"customers":[]}))
        send(parent, {:document, self(), document})

        receive do
          :close ->
            assert :ok = SimdJson.close(document)
            send(parent, {:closed, self()})
        end
      end)

    assert_receive {:document, ^owner, %Document{} = document}, 1_000

    normalized = StreamOptions.new(document, path: [], fields: [id: ["id"]])
    assert StreamOptions.snapshot_for_test(normalized).source_kind == :document
    assert StreamOptions.snapshot_for_test(normalized).owner_matches

    send(owner, :close)
    assert_receive {:closed, ^owner}, 1_000

    closed = StreamOptions.new(document, path: [], fields: [id: ["id"]])
    assert StreamOptions.snapshot_for_test(closed).source_kind == :document
  end

  # covers: simd_json.streaming_api.target_path simd_json.streaming_api.fields_projection simd_json.streaming_api.milestone_scope
  test "large unique binary targets and fields never grow the atom table" do
    target_path = for index <- 0..1_999, do: "target-#{index}"

    fields =
      for index <- 0..1_999 do
        {"output-#{index}", ["field-#{index}", index]}
      end

    _warm = StreamOptions.new("warm", path: ["warm"], fields: [{"warm", ["warm"]}])
    :erlang.garbage_collect(self())
    before = :erlang.system_info(:atom_count)

    normalized = StreamOptions.new("not JSON", path: target_path, fields: fields)
    snapshot = StreamOptions.snapshot_for_test(normalized)

    assert snapshot.target_path == target_path
    assert length(snapshot.fields.entries) == 2_000
    assert length(snapshot.fields.paths) == 2_000
    assert :erlang.system_info(:atom_count) == before
  end

  defp wait_for_quiescence(attempts \\ 400)

  defp wait_for_quiescence(0) do
    flunk(
      "native operation did not quiesce: #{inspect(BuildSmoke.execution_snapshot())}; " <>
        "coordinator=#{inspect(OperationCoordinator.snapshot())}"
    )
  end

  defp wait_for_quiescence(attempts) do
    :erlang.garbage_collect(self())
    native = BuildSmoke.execution_snapshot()

    if OperationCoordinator.snapshot().live_requests == 0 and native.queued_operations == 0 and
         native.running_operations == 0 do
      :ok
    else
      Process.sleep(5)
      wait_for_quiescence(attempts - 1)
    end
  end
end
