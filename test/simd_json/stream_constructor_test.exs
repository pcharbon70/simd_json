defmodule SimdJson.StreamConstructorTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildSmoke
  alias SimdJson.Stream

  test "constructs an opaque redacted stream without native work" do
    baseline = BuildSmoke.execution_snapshot()
    secret = "constructor-secret"

    stream =
      SimdJson.stream(~s([{"#{secret}":1}]),
        path: [],
        fields: [{:value, [secret]}],
        batch_size: 2,
        max_batch_bytes: 1_024
      )

    assert %Stream{} = stream

    assert inspect(stream) ==
             "#SimdJson.Stream<source: :binary, batch_size: 2, max_batch_bytes: 1024>"

    refute inspect(stream) =~ secret
    assert BuildSmoke.execution_snapshot() == baseline
  end

  test "validates the complete public contract synchronously" do
    assert_raise ArgumentError, fn -> SimdJson.stream(:invalid, path: [], fields: [v: ["v"]]) end
    assert_raise ArgumentError, fn -> SimdJson.stream("[]", []) end

    assert_raise ArgumentError, fn ->
      SimdJson.stream("[]", path: [], fields: [v: ["v"]], batch_size: 0)
    end
  end
end
