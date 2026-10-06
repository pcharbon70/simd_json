# 01 — Getting Started

<!-- covers: simd_json.package.documentation_layout -->

This guide takes you from installation to your first decoded value, selected
fields, and lazy file stream. You can paste each Elixir example into
`iex -S mix`.

## Install SimdJson

Add `simd_json` to the dependencies in your `mix.exs`:

```elixir
def deps do
  [
    {:simd_json, "~> 0.1.0"}
  ]
end
```

Fetch the package and compile your project:

```sh
mix deps.get
mix compile
```

On Ubuntu 24.04 x86-64, Mix downloads a checksum-verified native library. You
do not need Zig, a C++ compiler, or a separate simdjson installation.

Start an IEx session and make sure everything works:

```elixir
iex> SimdJson.decode(~s({"hello":"world"}))
{:ok, %{"hello" => "world"}}
```

If compilation reports an unsupported native target, see
[06 — Deployment and Native Delivery](06-deployment.md).

## Decode a complete value

Imagine that an HTTP response contains an account and its recent activity:

```elixir
json = ~s({
  "account": {"id": 7, "name": "Northwind"},
  "events": ["signed_in", "exported_report"]
})

{:ok, data} = SimdJson.decode(json)

data["account"]["name"]
# => "Northwind"
```

`decode/1` is the simplest choice when your application needs most or all of
the JSON. It returns ordinary Elixir maps, lists, binaries, numbers, booleans,
and `nil`.

## Return only the fields you need

If you only need the account identifier and name, ask SimdJson for those
fields directly:

```elixir
{:ok, account} =
  SimdJson.select(json,
    id: ["account", "id"],
    name: ["account", "name"]
  )

account
# => %{id: 7, name: "Northwind"}
```

Each entry has an output key on the left and a path through the JSON on the
right. Only the selected scalar values are returned to the BEAM.

## Process a large file lazily

For a large file of newline-delimited events, stream rows instead of decoding
the complete file. Create `events.ndjson`:

```json
{"id":1,"kind":"signed_in","internal":{"trace":"a1"}}
{"id":2,"kind":"exported_report","internal":{"trace":"b2"}}
{"id":3,"kind":"signed_out","internal":{"trace":"c3"}}
```

Now project and consume just `id` and `kind`:

```elixir
events =
  SimdJson.stream_file("events.ndjson",
    format: :ndjson,
    fields: [id: ["id"], kind: ["kind"]],
    batch_size: 500
  )

Enum.each(events, fn event ->
  IO.inspect(event, label: "event")
end)
```

The stream requests one bounded batch at a time. The native layer maps and
parses the file, while Elixir receives only the projected rows.

## Handle an error

Non-raising operations return a structured error:

```elixir
case SimdJson.decode(~s({"broken":])) do
  {:ok, value} ->
    value

  {:error, %SimdJson.Error{reason: reason, byte_offset: offset}} ->
    IO.puts("JSON failed near byte #{offset}: #{reason}")
end
```

Errors contain stable metadata but never embed the JSON source. Lazy streams
raise `SimdJson.Error` during enumeration because parsing happens as rows are
requested.

## Choose an API

- Use `decode/1` when you need the complete Elixir value.
- Use `select/2` when JSON is already a binary and you need a few scalars.
- Use `select_file/2` to select scalars without first reading the file into a
  BEAM binary.
- Use `stream_file/2` for row-oriented work, early stopping, and bounded
  parser and result-batch memory.

Next: [02 — Decoding JSON](02-decoding-json.md).
