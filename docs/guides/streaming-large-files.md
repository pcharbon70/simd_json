# Streaming Large Files

<!-- covers: simd_json.package.documentation_layout -->

`stream/2` and `stream_file/2` lazily project scalar fields from a sequence of
JSON rows. One row- and byte-bounded batch is requested per demand, with no
prefetch.

## Stream an array in a binary

```elixir
json = ~s({"orders":[{"sku":"A-1","total":19.95},{"sku":"B-2","total":5.0}]})

rows =
  SimdJson.stream(json,
    path: ["orders"],
    fields: [sku: ["sku"], total: ["total"]],
    batch_size: 500,
    max_batch_bytes: 8_388_608
  )

Enum.take(rows, 10)
```

Construction validates options but performs no native work. Enumeration must
occur in the process that created the stream. Binary-backed streams are
replayable; document-backed streams are one-shot.

## Stream a file

```elixir
rows =
  SimdJson.stream_file("events.ndjson",
    format: :ndjson,
    fields: [id: ["id"], kind: ["kind"]],
    batch_size: 1_000,
    max_batch_bytes: 8_388_608
  )

Enum.reduce(rows, 0, fn row, count ->
  consume(row)
  count + 1
end)
```

The required `:format` is one of:

- `:json_array`
- `:ndjson`
- `:json_sequence`
- `:comma_delimited`

File streams operate on top-level documents and do not accept a nested
`:path`. The native layer owns the memory map and uses simdjson document
iteration with a fixed parser window. Consumed Linux mapping pages are advised
away at safe batch boundaries.

## Resource behavior

Selected strings are copied into result binaries. Early halt closes the native
cursor, parser, projection plan, and file mapping without scanning the rest of
the input:

```elixir
rows |> Stream.take(100) |> Enum.to_list()
```

A failing batch publishes no rows. Because enumeration is lazy, runtime
failures raise `SimdJson.Error` from the consuming operation.

Choose `batch_size` for downstream work granularity and
`max_batch_bytes` for a hard result-size ceiling. See
[Errors, Limits, and Performance](errors-limits-performance.md) for tuning and
memory boundaries.
