defmodule SimdJson.DecodeCompatibilityQualificationTest do
  use ExUnit.Case, async: false

  @valid [
    "null",
    "true",
    "false",
    "0",
    "-9223372036854775808",
    "18446744073709551615",
    "1.25e2",
    ~S("escapes: \" \\ \/ \b \f \n \r \t"),
    ~S("unicode: \u96ea \ud83d\ude80 \u0000"),
    "[]",
    "{}",
    ~S([null,true,false,0,-1,1.5,"x",[],{}]),
    ~S({"empty":"","array":[1,{"nested":[false,null]}]})
  ]

  @invalid [
    "",
    " ",
    <<0xEF, 0xBB, 0xBF, ?n, ?u, ?l, ?l>>,
    "null true",
    "[1,",
    ~S({"key":}),
    ~S("\ud800"),
    ~S("\udc00"),
    <<?\", 0xFF, ?\">>,
    "01",
    "1.",
    "1e",
    "1e9999"
  ]

  # covers: simd_json.decode_api.complete_values simd_json.decode_api.binary_keys simd_json.decode_api.exact_numbers simd_json.decode_api.compatible_materialization
  test "accepted corpus exactly matches pinned Jason values" do
    assert Application.spec(:jason, :vsn) |> to_string() == "1.4.5"

    for input <- @valid do
      assert {:ok, expected} = Jason.decode(input), input
      assert {:ok, actual} = SimdJson.decode(input), input
      assert actual === expected, input
    end
  end

  test "duplicate keys retain the documented last-value difference" do
    input = ~S({"duplicate":1,"duplicate":2,"duplicate":3})
    assert {:ok, %{"duplicate" => 1}} = Jason.decode(input)
    assert {:ok, %{"duplicate" => 3}} = SimdJson.decode(input)
  end

  # covers: simd_json.decode_api.shared_errors simd_json.decode_api.bounded_failure
  test "rejected corpus fails in both decoders without exposing input" do
    for input <- @invalid do
      assert {:error, _jason_error} = Jason.decode(input), inspect(input)
      assert {:error, %SimdJson.Error{} = error} = SimdJson.decode(input), inspect(input)
      if String.valid?(input) and String.trim(input) != "", do: refute(inspect(error) =~ input)
    end
  end

  test "generated nested values preserve exact structure" do
    values =
      Enum.reduce(1..64, [nil, true, false, 0, -1, 1.5, "雪"], fn depth, acc ->
        [%{"depth" => depth, "values" => acc}]
      end)

    encoded = Jason.encode!(values)
    assert {:ok, ^values} = SimdJson.decode(encoded)
  end
end
