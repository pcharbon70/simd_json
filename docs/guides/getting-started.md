# Getting Started

<!-- covers: simd_json.package.documentation_layout -->

`SimdJson` provides three ways to work with JSON:

- decode a complete value with `decode/1` or `decode!/1`;
- extract selected scalar fields with `select/2` or `select_file/2`;
- lazily stream projected rows with `stream/2` or `stream_file/2`.

## Install

Add the dependency to `mix.exs`:

```elixir
def deps do
  [
    {:simd_json, "~> 0.1.0"}
  ]
end
```

Then run:

```sh
mix deps.get
mix compile
```

Supported Ubuntu 24.04 x86-64 consumers receive a checksum-verified
precompiled NIF and do not need Zig or a C++ toolchain. See
[Deployment and Native Delivery](deployment.md) for other environments and
offline operation.

## Choose an API

Use `decode/1` when the application needs the entire JSON value:

```elixir
{:ok, value} = SimdJson.decode(~s({"ready":true,"items":[1,2,3]}))
```

Use `select/2` when the source is already a binary but only a few scalar values
are needed:

```elixir
{:ok, %{id: 7, active: true}} =
  SimdJson.select(~s({"account":{"id":7,"active":true}}),
    id: ["account", "id"],
    active: ["account", "active"]
  )
```

Use `select_file/2` for the same operation without first reading the file into
a BEAM binary:

```elixir
{:ok, %{id: 7}} =
  SimdJson.select_file("account.json", id: ["account", "id"])
```

Use `stream_file/2` for large arrays or document streams when memory must stay
bounded as rows are consumed:

```elixir
SimdJson.stream_file("events.ndjson",
  format: :ndjson,
  fields: [id: ["id"], kind: ["kind"]],
  batch_size: 500
)
|> Stream.take(10)
|> Enum.to_list()
```

## Errors

Non-bang operations return `{:ok, value}` or
`{:error, %SimdJson.Error{}}`. The error contains a stable reason and redacted
metadata; it never embeds JSON input. `decode!/1,2` raises the same structured
error. Streaming failures raise during enumeration because the work is lazy.

Continue with [Decoding JSON](decoding-json.md),
[Selecting Fields](selecting-fields.md), or
[Streaming Large Files](streaming-large-files.md).
