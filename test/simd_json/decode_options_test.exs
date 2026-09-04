defmodule SimdJson.DecodeOptionsTest do
  use ExUnit.Case, async: false

  alias SimdJson.DecodeOptions
  alias SimdJson.Native.BuildSmoke

  # covers: simd_json.decode_api.binary_input simd_json.decode_api.closed_options simd_json.decode_api.preflight
  test "accepts only binary input with an empty option list" do
    assert %DecodeOptions{} = options = DecodeOptions.new(~s({"value":1}), [])
    assert DecodeOptions.input(options) == ~s({"value":1})

    assert DecodeOptions.snapshot_for_test(options) == %{
             input_bytes: 11,
             option_count: 0,
             compatibility_reference: "jason-1.4.5",
             input_type: :binary
           }

    for source <- [nil, :json, ["{}"], {:json, "{}"}, 12] do
      assert_raise ArgumentError, "expected JSON input to be a binary", fn ->
        DecodeOptions.new(source, [])
      end
    end
  end

  # covers: simd_json.decode_api.closed_options simd_json.decode_api.preflight
  test "rejects every non-empty, improper, and non-list option shape" do
    for options <- [[keys: :atoms], [strings: :copy], [:invalid], [{:keys, :strings}]] do
      assert_raise ArgumentError, "decode options must be an empty list", fn ->
        DecodeOptions.new("null", options)
      end
    end

    for options <- [nil, :options, %{}, {:keys, :strings}, [keys: :strings] ++ :improper] do
      assert_raise ArgumentError, "decode options must be a proper list", fn ->
        DecodeOptions.new("null", options)
      end
    end
  end

  # covers: simd_json.decode_api.preflight
  test "preflight performs no native admission, parse, or lifecycle transition" do
    before = BuildSmoke.native_pool_snapshot()
    secret = "decode-preflight-secret-5401"

    options = DecodeOptions.new(~s({"private":"#{secret}"}), [])

    assert BuildSmoke.native_pool_snapshot() == before
    refute inspect(DecodeOptions.snapshot_for_test(options)) =~ secret
    refute inspect(DecodeOptions.snapshot_for_test(options)) =~ "private"
  end
end
