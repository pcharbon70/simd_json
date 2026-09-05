# SimdJson

An Elixir library for decoding JSON and extracting selected values with
SIMD-accelerated parsing.

## Public API

Decode a complete JSON binary with the Jason 1.4.5-compatible empty-option
contract:

```elixir
SimdJson.decode(~s({"ready":true,"items":[1,2,3]}))
# => {:ok, %{"ready" => true, "items" => [1, 2, 3]}}

SimdJson.decode!("null", [])
# => nil
```

Object keys and strings are copied binaries, duplicate keys use the last
value, arrays preserve order, and input never creates atoms. Only binary input
and `[]` options are accepted. Eager decode constructs the entire BEAM value;
for large payloads, prefer `select/2` or `stream/2` when practical.

Select several nested scalar values from a binary in one operation:

```elixir
json =
  ~s({"customer":{"id":1234,"name":"Acme"},"orders":[{"sku":"ABC-123"}]})

SimdJson.select(json, [
  {:id, ["customer", "id"]},
  {"name", ["customer", "name"]},
  {:first_sku, ["orders", 0, "sku"]}
])
# => {:ok, %{"name" => "Acme", id: 1234, first_sku: "ABC-123"}}
```

Output keys are the exact existing atoms or binaries supplied by the caller;
JSON keys are never atomized. Paths contain UTF-8 binary object keys and
unsigned 64-bit array indexes. Only string, integer, float, boolean, and null
leaves are returned. Selecting an object or array yields `:incorrect_type`
without building that container.

The complete source is validated even after all requested values have been
found. The first occurrence of a repeated requested object key supplies its
value. Every selected string is copied into a fresh result binary, so a small
result does not retain a large source. Any parse, path, type, range,
allocation, or cancellation failure returns one `SimdJson.Error` and no
partial map.

For deterministic native lifetime, open a document and select from it once:

```elixir
case SimdJson.open(~s({"items": [1, 2, 3], "ready": true})) do
  {:ok, document} ->
    {:ok, %{item: 2, ready: true}} =
      SimdJson.select(document, item: ["items", 1], ready: ["ready"])

    :ok = SimdJson.close(document)

  {:error, %SimdJson.Error{reason: reason}} ->
    {:error, reason}
end
```

`SimdJson.open/1` accepts binaries only. A document belongs to the process that
opened it, owner close is idempotent, and another process receives `:not_owner`
without learning whether the document is open or closed. Once a selection
worker accesses its forward-only cursor, success and failure both consume the
document. Another projection requires another document, or another
`SimdJson.select/2` call with the binary; there is no transparent rewind,
reparse, or reusable public compiled plan.

Invalid projection grammar returns `:invalid_projection` before JSON parsing or
document reservation. A source that is neither a binary nor a genuine
`SimdJson.Document` raises `ArgumentError`. Errors and document inspection omit
JSON content, caller path contents, native identity, timing, generation, and
exception text.

The public root operations are `decode/1,2`, `decode!/1,2`, `open/1`,
`select/2`, `stream/2`, and `close/1`. There is no projection bang variant,
JSONPath, wildcard/filter/default policy, streaming cursor, ownership transfer,
raw native handle, or public diagnostic API. The active Milestone 4 runtime routes native work
through a bounded worker pool and non-blocking queue configured at application
startup. Saturation
returns the existing redacted `:busy` error.

Operational telemetry uses the standard `:telemetry` events
`[:simd_json, :job, :start | :stop | :exception | :cancelled]` and
`[:simd_json, :queue, :rejected]`. Metadata is limited to operation and outcome;
measurements contain bounded capacity, size, and duration values and never JSON
content, paths, PIDs, request references, or native addresses.

Milestone 5 implements its safe Jason 1.4.5 compatibility subset through an
iterative native materializer and bounded-pool execution. The compatibility
surface intentionally excludes iodata, key atomization, structs, custom
decoders, decimal modes, and every non-empty option list. The supported
behavior, qualification boundary, and evidence contract are recorded in the
[Milestone 5 acceptance record](docs/milestones/05-compatible-decode-api-acceptance.md).

Stream a root or nested array lazily with a scalar projection:

```elixir
rows =
  SimdJson.stream(json,
    path: ["orders"],
    fields: [sku: ["sku"], total: ["total"]],
    batch_size: 500,
    max_batch_bytes: 8_388_608
  )

Enum.take(rows, 10)
```

`SimdJson.stream/2` validates options immediately but performs no native work
until its creating process begins enumeration. Binaries are replayable;
documents are owner-bound and one-shot. Each returned string is a fresh result
binary. One row-and-byte-bounded batch is requested at a time with no prefetch,
and early halt closes the cursor without scanning the remaining array. Runtime
failures raise a redacted `SimdJson.Error`; no row from a failing batch is
published. The opaque Enumerable exposes no public cursor or batch API.

Milestones 1, 2, and 3 are active on the qualified Ubuntu 24.04 x86-64 target.
Other platforms remain experimental or unsupported until they pass the same
package, ABI, sanitizer, scheduler, lifecycle, benchmark, and shutdown gates.

## License

SimdJson wrapper code is available under the [MIT License](LICENSE).
The vendored simdjson source retains its upstream license choices and
attribution, described in [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Development

Install dependencies and run the test suite:

```sh
mix deps.get
mix test
```

The Milestone 1 architecture and acceptance boundary are documented in
[`docs/milestones/01-native-foundation.md`](docs/milestones/01-native-foundation.md).
Maintainers should also read the
[`Milestone 1 Native Foundation Operations`](docs/milestones/01-native-foundation-operations.md)
guide before changing a native dependency, ownership rule, or threaded
execution boundary. The
[`Milestone 1 Acceptance Record`](docs/milestones/01-native-foundation-acceptance.md)
identifies the qualified target, immutable evidence, and remaining non-goals.
The projection grammar, traversal, and lifecycle are documented in
[`docs/milestones/02-projection-api.md`](docs/milestones/02-projection-api.md).
Maintainers should also read the
[`Milestone 2 Projection API Operations`](docs/milestones/02-projection-api-operations.md)
guide and
[`Milestone 2 Projection API Acceptance Record`](docs/milestones/02-projection-api-acceptance.md)
before changing the projection or qualification boundary.
The public streaming contract and tuning guidance are documented in
[`docs/milestones/03-batched-array-streaming.md`](docs/milestones/03-batched-array-streaming.md).
Maintainers should also read the
[`Milestone 3 Streaming Operations`](docs/milestones/03-batched-array-streaming-operations.md)
guide and
[`Milestone 3 Acceptance Record`](docs/milestones/03-batched-array-streaming-acceptance.md)
before changing batch, cursor, lifecycle, or qualification behavior.
