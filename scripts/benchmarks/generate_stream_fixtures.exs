seed = 260_902_003
root = Path.expand("../..", __DIR__)
directory = Path.join(root, "bench/stream_fixtures")
File.mkdir_p!(directory)

fixtures = [
  %{name: :small, rows: 100, nested: false},
  %{name: :medium, rows: 10_000, nested: true},
  %{name: :million, rows: 1_000_000, nested: false}
]

manifest =
  Enum.map(fixtures, fn fixture ->
    rows =
      1..fixture.rows
      |> Stream.map(fn index ->
        ~s({"id":#{index},"value":#{index},"ignored":"#{rem(index + seed, 10_000)}"})
      end)
      |> Enum.intersperse(",")

    json =
      if fixture.nested do
        [~s({"payload":{"rows":[), rows, "]}}"]
      else
        ["[", rows, "]"]
      end
      |> IO.iodata_to_binary()

    compressed = :zlib.gzip(json)
    path = Path.join(directory, "#{fixture.name}.json.gz")
    File.write!(path, compressed)

    %{
      name: fixture.name,
      rows: fixture.rows,
      nested: fixture.nested,
      path: Path.relative_to(path, root),
      bytes: byte_size(json),
      compressed_bytes: byte_size(compressed),
      sha256: :crypto.hash(:sha256, json) |> Base.encode16(case: :lower),
      expected_sum: fixture.rows * (fixture.rows + 1)
    }
  end)

huge_row = ~s([{"id":1,"value":1,"ignored":"#{String.duplicate("x", 1_048_576)}"}])
huge_path = Path.join(directory, "huge-row.json.gz")
File.write!(huge_path, :zlib.gzip(huge_row))

manifest = %{
  schema_version: 1,
  seed: seed,
  generator: "scripts/benchmarks/generate_stream_fixtures.exs",
  projection: [id: ["id"], value: ["value"]],
  fixtures: manifest,
  huge_row: %{
    path: Path.relative_to(huge_path, root),
    bytes: byte_size(huge_row),
    sha256: :crypto.hash(:sha256, huge_row) |> Base.encode16(case: :lower)
  }
}

File.write!(
  Path.join(directory, "manifest.exs"),
  inspect(manifest, pretty: true, limit: :infinity) <> "\n"
)

IO.puts("generated deterministic stream fixtures seed=#{seed}")
