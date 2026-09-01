defmodule SimdJson.StreamOptionsTest do
  use ExUnit.Case, async: false

  alias SimdJson.StreamOptions

  @max_u64 18_446_744_073_709_551_615
  @fields [
    {:id, ["customer", "id"]},
    {"same-id", ["customer", "id"]},
    {"unicode", ["雪", 0, @max_u64]}
  ]

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
end
