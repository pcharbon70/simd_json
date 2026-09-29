defmodule SimdJson.FileStreamTest do
  use ExUnit.Case, async: false

  alias SimdJson.Error

  @tag :tmp_dir
  test "streams every explicit top-level file format in bounded batches", %{tmp_dir: tmp_dir} do
    cases = [
      {:json_array, ~s([{"value":1},{"value":2},{"value":3}])},
      {:ndjson, "{\"value\":1}\n{\"value\":2}\n{\"value\":3}\n"},
      {:json_sequence,
       <<0x1E, ~s({"value":1})::binary, ?\n, 0x1E, ~s({"value":2})::binary, ?\n, 0x1E,
         ~s({"value":3})::binary, ?\n>>},
      {:comma_delimited, ~s({"value":1},{"value":2},{"value":3})}
    ]

    for {format, contents} <- cases do
      path = Path.join(tmp_dir, Atom.to_string(format))
      File.write!(path, contents)

      assert SimdJson.stream_file(path,
               format: format,
               fields: [value: ["value"]],
               batch_size: 2,
               max_batch_bytes: 1_024
             )
             |> Enum.to_list() == [%{value: 1}, %{value: 2}, %{value: 3}]
    end
  end

  @tag :tmp_dir
  test "halts early without parsing the malformed remainder", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "early.ndjson")
    File.write!(path, "{\"value\":1}\n{malformed later")

    assert SimdJson.stream_file(path,
             format: :ndjson,
             fields: [value: ["value"]],
             batch_size: 1
           )
           |> Enum.take(1) == [%{value: 1}]
  end

  @tag :tmp_dir
  test "reports a malformed later document at its stable row index", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "malformed.ndjson")
    File.write!(path, "{\"value\":1}\n{malformed")

    stream =
      SimdJson.stream_file(path,
        format: :ndjson,
        fields: [value: ["value"]],
        batch_size: 1
      )

    error = assert_raise Error, fn -> Enum.to_list(stream) end
    assert error.reason == :unexpected_eof
    assert error.array_index == 1
  end

  @tag :tmp_dir
  test "detects file mutation between demanded batches", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "mutable.ndjson")
    File.write!(path, "{\"value\":1}\n{\"value\":2}\n")

    stream =
      SimdJson.stream_file(path,
        format: :ndjson,
        fields: [value: ["value"]],
        batch_size: 1
      )

    assert {:suspended, [%{value: 1}], continuation} =
             Enumerable.reduce(stream, {:cont, []}, fn row, rows -> {:suspend, [row | rows]} end)

    File.write!(path, "{\"value\":1}\n{\"value\":20}\n")

    assert_raise Error, fn -> continuation.({:cont, []}) end
  end

  test "validates file options before native work" do
    assert_raise ArgumentError, fn -> SimdJson.stream_file("file.json", fields: [v: ["v"]]) end

    assert_raise ArgumentError, fn ->
      SimdJson.stream_file("file.json", format: :unknown, fields: [v: ["v"]])
    end

    assert_raise ArgumentError, fn ->
      SimdJson.stream_file("file.json", format: :json_array, fields: [v: ["v"]], path: [])
    end
  end

  @tag :tmp_dir
  test "keeps reduction owner-bound and reports stable file errors", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "owned.json")
    File.write!(path, ~s([{"value":1}]))

    stream = SimdJson.stream_file(path, format: :json_array, fields: [value: ["value"]])

    assert {:error, %Error{reason: :not_owner}} =
             Task.async(fn ->
               try do
                 Enum.to_list(stream)
               rescue
                 error in Error -> {:error, error}
               end
             end)
             |> Task.await()

    missing =
      SimdJson.stream_file(Path.join(tmp_dir, "missing.json"),
        format: :json_array,
        fields: [value: ["value"]]
      )

    assert_raise Error, "JSON file was not found", fn -> Enum.to_list(missing) end
  end
end
