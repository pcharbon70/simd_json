defmodule SimdJson.DecodeApiTest do
  use ExUnit.Case, async: true

  alias SimdJson.Error

  # covers: simd_json.decode_api.complete_values simd_json.decode_api.binary_keys simd_json.decode_api.exact_numbers
  test "materializes every top-level JSON value through the public API" do
    cases = [
      {~S({"a":1,"a":2}), %{"a" => 2}},
      {"[]", []},
      {~S("snow: \u96ea"), "snow: 雪"},
      {"-9223372036854775808", -9_223_372_036_854_775_808},
      {"18446744073709551615", 18_446_744_073_709_551_615},
      {"1.25e2", 125.0},
      {"true", true},
      {"false", false},
      {"null", nil}
    ]

    for {input, expected} <- cases do
      assert {:ok, ^expected} = SimdJson.decode(input)
      assert SimdJson.decode!(input, []) == expected
    end
  end

  # covers: simd_json.decode_api.complete_values simd_json.decode_api.shared_errors
  test "tagged and raising forms share the same structured parse error" do
    assert {:error, %Error{} = tagged} = SimdJson.decode(~S({"value":))
    assert tagged.reason == :unexpected_eof
    assert is_nil(tagged.byte_offset) or is_integer(tagged.byte_offset)
    assert tagged.message == "unexpected end of JSON input"

    raised = assert_raise Error, fn -> SimdJson.decode!(~S({"value":)) end
    assert Map.from_struct(raised) == Map.from_struct(tagged)
    refute inspect(tagged) =~ ~S({"value":)
  end

  test "out-of-range numbers use the stable shared reason" do
    input = "184467440/beef"
    input = String.replace(input, "/beef", "73709551616")

    assert {:error, %Error{reason: :number_out_of_range}} = SimdJson.decode(input)
    assert_raise Error, fn -> SimdJson.decode!(input) end
  end

  test "preflight failures raise ArgumentError before native admission" do
    assert_raise ArgumentError, "expected JSON input to be a binary", fn ->
      SimdJson.decode(["null"])
    end

    assert_raise ArgumentError, "decode options must be an empty list", fn ->
      SimdJson.decode("null", keys: :atoms)
    end
  end
end
