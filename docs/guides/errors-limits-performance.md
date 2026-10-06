# Errors, Limits, and Performance

## Error model

Non-streaming operations return `{:ok, value}` or
`{:error, %SimdJson.Error{}}`. Stable reasons cover parsing, missing paths,
incorrect scalar types, numeric range, ownership, consumed cursors, allocation,
cancellation, and worker-pool saturation.

Errors are deliberately redacted. Inspection omits JSON content, projection
paths, process identifiers, native addresses, request references, timing, and
exception text. A projection failure returns no partial map; a streaming batch
failure publishes no rows.

The fixed bounded worker pool uses a bounded queue. When the queue is full, new
work returns `:busy` rather than falling back to scheduler-blocking execution.

## Input and memory boundary

| API | Source residency | Result allocation |
| --- | --- | --- |
| `decode/1,2` | complete BEAM binary | complete Elixir value |
| `select/2` | complete BEAM binary | selected scalars only |
| `stream/2` | complete BEAM binary | one bounded result batch per demand |
| `open_file/1` / `select_file/2` | native file mapping | document state or selected scalars |
| `stream_file/2` | native file mapping with bounded parser windows | one bounded result batch per demand |

`select_file/2` avoids a BEAM source copy but simdjson structural indexes may
still scale with input size. `stream_file/2` is the bounded-parser-memory path.
Mapped pages may contribute to process RSS even when they are reclaimable; RSS
is not the same measurement as retained BEAM heap or live native allocations.

## Choosing the fastest useful operation

- Use `decode/1` only when the complete value is required.
- Use `select/2` or `select_file/2` when a small, known set of scalar fields is
  sufficient.
- Use `stream/2` or `stream_file/2` for row-oriented pipelines and early halt.
- Increase `batch_size` to reduce request overhead when rows are small.
- Lower `max_batch_bytes` when result strings can be large or downstream work
  needs a tighter memory ceiling.

Every selected string is copied into a fresh binary so small results do not
retain large sources. File inputs must remain immutable while an operation is
active.

## Intentional limits

The library does not support iodata, atomizing JSON keys, JSONPath,
wildcards, filters, default fields, public compiled projections, ownership
transfer, raw native handles, socket/device input, or nested-path file
streaming. `decode/2` accepts only `[]`.

See the [Benchmark Reports](../benchmarks/README.md) for measured comparisons
and the exact fixture shapes used by each report.
