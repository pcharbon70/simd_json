# 04 — Streaming Large Files

<!-- covers: simd_json.package.documentation_layout -->

This tutorial builds a lazy event pipeline that reads a large JSON file one
bounded batch at a time. It is the best starting point when you want selected
fields from many rows without loading the complete file into a BEAM binary.

## Create a practice file

Create `events.ndjson` with one JSON object per line:

```json
{"id":1,"kind":"signed_in","account":{"plan":"free"}}
{"id":2,"kind":"exported_report","account":{"plan":"business"}}
{"id":3,"kind":"signed_out","account":{"plan":"business"}}
```

The same code will work when the real file contains millions of rows.

## Construct the stream

Tell SimdJson the file format and which scalar fields each row should return:

```elixir
events =
  SimdJson.stream_file("events.ndjson",
    format: :ndjson,
    fields: [
      id: ["id"],
      kind: ["kind"],
      plan: ["account", "plan"]
    ],
    batch_size: 500,
    max_batch_bytes: 8_388_608
  )
```

Nothing has been parsed yet. Stream construction validates the options, but
native work begins only when an `Enum` or `Stream` operation asks for rows.

## Consume rows with normal Enum functions

`SimdJson.Stream` implements `Enumerable`, so it fits into ordinary Elixir
pipelines:

```elixir
business_exports =
  events
  |> Stream.filter(&(&1.plan == "business"))
  |> Stream.filter(&(&1.kind == "exported_report"))
  |> Enum.map(& &1.id)

# => [2]
```

Enumeration must happen in the process that created the stream. This keeps
cursor ownership and cleanup deterministic.

## Stop early

You do not have to scan the rest of a file when you already have enough rows:

```elixir
first_hundred =
  events
  |> Stream.take(100)
  |> Enum.to_list()
```

Early termination closes the native cursor, parser, projection plan, and file
mapping. It does not continue parsing in the background.

## Choose the input format

`stream_file/2` requires a `:format` option:

| Format | File shape |
| --- | --- |
| `:ndjson` | one JSON document per line |
| `:json_array` | one top-level JSON array |
| `:json_sequence` | RFC 7464-style record-separated documents |
| `:comma_delimited_json` | top-level JSON documents separated by commas |

File streams operate on top-level documents and do not accept a nested
`:path`.

If the JSON is already a binary and rows live in a nested array, use
`stream/2` instead:

```elixir
json = ~s({"orders":[{"sku":"A-1","total":19.95},{"sku":"B-2","total":5.0}]})

orders =
  SimdJson.stream(json,
    path: ["orders"],
    fields: [sku: ["sku"], total: ["total"]],
    batch_size: 100
  )

Enum.to_list(orders)
# => [%{sku: "A-1", total: 19.95}, %{sku: "B-2", total: 5.0}]
```

Binary-backed streams can be enumerated again. Streams backed by an explicitly
opened document are one-shot.

## Tune batch bounds

Two options control how much result data crosses into Elixir per demand:

- `batch_size` limits the number of rows.
- `max_batch_bytes` limits their encoded result size.

Start with the defaults. Increase `batch_size` when rows are small and request
overhead is visible. Lower `max_batch_bytes` when selected strings can be
large or downstream work needs a tighter memory ceiling. Both limits apply;
the next batch stops at whichever boundary comes first.

Selected strings are copied into fresh result binaries. The native layer owns
the file mapping and uses fixed parser windows; safely consumed Linux mapping
pages are advised away at batch boundaries.

## Handle a failure during enumeration

Because parsing is lazy, malformed input can fail after earlier rows have been
consumed:

```elixir
try do
  Enum.each(events, &send_to_destination/1)
rescue
  error in SimdJson.Error ->
    Logger.error("event import failed: #{inspect(error)}")
end
```

A failing native batch publishes none of its rows. If the destination must be
transactional across the complete file, add that transaction or staging layer
around your consumer.

Previous: [03 — Selecting Fields](03-selecting-fields.md)  
Next: [05 — Errors, Limits, and Performance](05-errors-limits-performance.md)
