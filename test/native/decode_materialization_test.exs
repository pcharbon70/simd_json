defmodule SimdJson.Native.DecodeMaterializationTest do
  use ExUnit.Case, async: true

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Native.ThreadedOperation

  test "constructs all JSON value kinds in a threaded private environment" do
    input =
      ~S({"array":[{},null,true,false,"x\u0000\u96ea"],"i":-9223372036854775808,"u":18446744073709551615,"n":1.25e2})

    assert {:ok,
            %{
              "array" => [%{}, nil, true, false, "x\0雪"],
              "i" => -9_223_372_036_854_775_808,
              "u" => 18_446_744_073_709_551_615,
              "n" => 125.0
            }} = BuildSmoke.threaded_decode_fixture(input)
  end

  test "object construction preserves the last duplicate key" do
    assert {:ok, %{"key" => 3}} =
             BuildSmoke.threaded_decode_fixture(~S({"key":1,"key":2,"key":3}))
  end

  test "routes eager decode through the bounded native pool" do
    assert {:ok, %{"value" => [1, 2, 3]}} =
             ThreadedOperation.decode(~S({"value":[1,2,3]}))

    assert {:error, %{reason: :unexpected_eof}} =
             ThreadedOperation.decode(~S({"value":))
  end

  test "publishes tagged and raising decode wrappers over the same operation" do
    assert {:ok, %{"value" => [1, true, nil]}} = SimdJson.decode(~S({"value":[1,true,null]}))
    assert %{"value" => [1, true, nil]} = SimdJson.decode!(~S({"value":[1,true,null]}), [])
  end
end
