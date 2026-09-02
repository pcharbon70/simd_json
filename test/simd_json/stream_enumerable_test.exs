defmodule SimdJson.StreamEnumerableTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error

  test "reduces rows lazily in order across exact native batches" do
    stream =
      SimdJson.stream(~s([{"value":1},{"value":2},{"value":3}]),
        path: [],
        fields: [value: ["value"]],
        batch_size: 2,
        max_batch_bytes: 1_024
      )

    assert Enum.to_list(stream) == [%{value: 1}, %{value: 2}, %{value: 3}]
  end

  test "early halt closes without consuming the remainder" do
    stream =
      SimdJson.stream(~s([{"value":1},{"value":2},{"value":3}]),
        path: [],
        fields: [value: ["value"]],
        batch_size: 1
      )

    assert Enum.take(stream, 1) == [%{value: 1}]
  end

  test "supports nested targets, multiple exact keys, and copied strings" do
    json =
      ~s({"data":{"rows":[{"id":1,"profile":{"name":"Ada"}},{"id":2,"profile":{"name":"Lin"}}]}})

    rows =
      json
      |> SimdJson.stream(
        path: ["data", "rows"],
        fields: [{:id, ["id"]}, {"name", ["profile", "name"]}],
        batch_size: 1
      )
      |> Enum.to_list()

    assert rows == [%{:id => 1, "name" => "Ada"}, %{:id => 2, "name" => "Lin"}]
  end

  test "reduction is owner-bound" do
    stream = SimdJson.stream("[]", path: [], fields: [value: ["value"]])

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn ->
               try do
                 Enum.to_list(stream)
               rescue
                 error in Error -> {:error, error}
               end
             end)
             |> Task.await()
  end

  test "document streaming is one-shot and owner close stays idempotent" do
    {:ok, document} = SimdJson.open(~s([{"value":7}]))
    stream = SimdJson.stream(document, path: [], fields: [value: ["value"]])

    assert Enum.to_list(stream) == [%{value: 7}]
    assert_raise Error, fn -> Enum.to_list(stream) end
    assert :ok = SimdJson.close(document)
    assert :ok = SimdJson.close(document)
  end
end
