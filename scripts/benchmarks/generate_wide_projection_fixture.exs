defmodule SimdJson.Benchmarks.GenerateWideProjectionFixture do
  @rows 1_000_000
  @field_count 16
  @chunk_rows 1_000

  def run do
    root = File.cwd!()
    directory = Path.join(root, "bench/wide_projection_fixture")
    path = Path.join(directory, "million-wide-16.json.gz")
    File.mkdir_p!(directory)

    {bytes, digest} = write_fixture(path)
    compressed_bytes = File.stat!(path).size

    manifest = %{
      schema_version: 1,
      generator: "scripts/benchmarks/generate_wide_projection_fixture.exs",
      fixture: %{
        name: :million_wide_16,
        path: Path.relative_to(path, root),
        rows: @rows,
        fields_per_row: @field_count,
        bytes: bytes,
        compressed_bytes: compressed_bytes,
        sha256: Base.encode16(digest, case: :lower)
      },
      field_names: field_names(),
      value_rule: "field fNN at one-based row R equals R + NN"
    }

    File.write!(
      Path.join(directory, "manifest.exs"),
      inspect(manifest, pretty: true, limit: :infinity) <> "\n"
    )

    IO.puts(
      "generated wide fixture rows=#{@rows} fields=#{@field_count} " <>
        "bytes=#{bytes} compressed_bytes=#{compressed_bytes}"
    )
  end

  defp write_fixture(path) do
    zlib = :zlib.open()
    :ok = :zlib.deflateInit(zlib, 6, :deflated, 31, 8, :default)
    hash = :crypto.hash_init(:sha256)

    try do
      File.open!(path, [:write, :binary], fn file ->
        {bytes, hash} = write_chunk(file, zlib, hash, "[")

        {bytes, hash} =
          1..@rows
          |> Stream.chunk_every(@chunk_rows)
          |> Enum.reduce({bytes, hash}, fn indexes, {byte_count, hash_state} ->
            prefix = if hd(indexes) == 1, do: "", else: ","
            chunk = [prefix, indexes |> Enum.map(&row/1) |> Enum.intersperse(",")]
            binary = IO.iodata_to_binary(chunk)
            write_chunk(file, zlib, hash_state, binary, byte_count)
          end)

        {bytes, hash} = write_chunk(file, zlib, hash, "]", bytes)
        IO.binwrite(file, :zlib.deflate(zlib, <<>>, :finish))
        {bytes, :crypto.hash_final(hash)}
      end)
    after
      :ok = :zlib.deflateEnd(zlib)
      :zlib.close(zlib)
    end
  end

  defp write_chunk(file, zlib, hash, binary, bytes \\ 0) do
    IO.binwrite(file, :zlib.deflate(zlib, binary, :sync))
    {bytes + byte_size(binary), :crypto.hash_update(hash, binary)}
  end

  defp row(index) do
    fields =
      field_names()
      |> Enum.with_index()
      |> Enum.map(fn {name, offset} -> [~s("#{name}":), Integer.to_string(index + offset)] end)
      |> Enum.intersperse(",")

    ["{", fields, "}"]
  end

  defp field_names do
    for index <- 0..(@field_count - 1),
        do: "f#{String.pad_leading(Integer.to_string(index), 2, "0")}"
  end
end

SimdJson.Benchmarks.GenerateWideProjectionFixture.run()
