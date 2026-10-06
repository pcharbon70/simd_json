# 05 — Errors, Limits, and Performance

Once your first integration works, this guide helps you choose the right API,
respond to failures, and reason about memory without relying on misleading
single-number measurements.

## Choose the smallest useful operation

Start with what your application actually needs:

1. If it needs the complete JSON value, use `decode/1`.
2. If it needs a known set of scalar fields, use `select/2` or
   `select_file/2`.
3. If it processes many similar rows, use `stream/2` or `stream_file/2`.

For example, this decodes every field:

```elixir
{:ok, order} = SimdJson.decode(json)
```

This returns only two scalar values:

```elixir
{:ok, summary} =
  SimdJson.select(json,
    id: ["order", "id"],
    total: ["order", "total"]
  )
```

And this lazily processes selected fields from every row:

```elixir
total =
  SimdJson.stream_file("orders.ndjson",
    format: :ndjson,
    fields: [id: ["id"], total: ["total"]]
  )
  |> Enum.reduce(0.0, fn row, sum -> sum + row.total end)
```

Doing less work at the API boundary is usually more valuable than tuning a
complete decode your application did not need.

## Understand where memory lives

The APIs have different source and result costs:

| API | Source behavior | Elixir result |
| --- | --- | --- |
| `decode/1,2` | complete BEAM binary | complete value tree |
| `select/2` | complete BEAM binary | selected scalars |
| `stream/2` | complete BEAM binary | one bounded batch per demand |
| `open_file/1` / `select_file/2` | native file mapping | document state or selected scalars |
| `stream_file/2` | native mapping and fixed parser windows | one bounded batch per demand |

`select_file/2` avoids copying the complete source into a BEAM binary, but its
one-shot simdjson structural indexes may still grow with the input.
`stream_file/2` is the bounded-parser-memory option for row-oriented sources.

Mapped file pages can appear in process RSS even when the operating system can
reclaim them. RSS therefore does not mean “memory permanently retained by the
library.” When investigating memory, distinguish BEAM heap, live native
allocations, mapped pages, and the size of results your application keeps.

## Tune a stream from safe defaults

Start without custom bounds, measure the real workload, and then adjust:

- Increase `batch_size` when rows are small and per-request overhead matters.
- Lower `max_batch_bytes` when projected strings can be large.
- Stop early with `Stream.take/2` when the consumer only needs a prefix.
- Select fewer fields when downstream code discards values immediately.

Every selected string is copied into a fresh binary, so keeping a small result
does not keep a large source alive as a substring.

## Handle expected failures

Non-streaming operations use tagged results:

```elixir
case SimdJson.select(json, id: ["account", "id"]) do
  {:ok, %{id: id}} ->
    {:ok, id}

  {:error, %SimdJson.Error{reason: :path_not_found}} ->
    {:error, :missing_account_id}

  {:error, %SimdJson.Error{reason: :busy}} ->
    {:error, :try_again_later}

  {:error, %SimdJson.Error{} = error} ->
    {:error, error}
end
```

Native work uses a fixed bounded worker pool. When its queue is full, new work
returns `:busy`; it does not fall back to blocking a scheduler.

Streams raise `SimdJson.Error` during enumeration because their work is lazy.
A failing projection returns no partial map, and a failing stream batch
publishes none of that batch's rows.

Errors are deliberately redacted. Inspection omits the JSON source, projection
paths, process identifiers, native addresses, request references, timings, and
native exception text.

## Work within the intentional scope

SimdJson keeps its public surface deliberately small. It does not currently
support iodata input, atomizing JSON keys, JSONPath, wildcards, filters,
default field values, public compiled projections, ownership transfer, raw
native handles, socket or device input, or nested-path file streaming.
`decode/2` accepts only `[]`.

These boundaries make validation, ownership, memory, and error behavior
predictable. If you need a complete nested object or array, decode it. If you
need a few scalar leaves, select them. If you need repeated rows, stream them.

For measured results and exact fixture shapes, see the
[Benchmark Reports](../benchmarks/README.md).

Previous: [04 — Streaming Large Files](04-streaming-large-files.md)  
Next: [06 — Deployment and Native Delivery](06-deployment.md)
