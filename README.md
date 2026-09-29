# SimdJson

An Elixir library for decoding JSON and extracting selected values with
SIMD-accelerated parsing. Native file-backed APIs keep large JSON sources out
of BEAM binaries and delegate mapping, parsing, and batching to simdjson.

## Installation

Add `simd_json` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:simd_json, "~> 0.1.0"}
  ]
end
```

Fetch dependencies and compile:

```sh
mix deps.get
mix compile
```

On the qualified Ubuntu 24.04 x86-64 target, compilation downloads the exact
versioned NIF from the matching GitHub release and verifies its committed
SHA-256 digest before loading it. Ordinary package consumers do not need Zig,
Zigler, a C++ compiler, or a system simdjson installation. Read the
[installation and native build guide](docs/releases/installation.md) before
deploying; it covers network and cache behavior, the explicit maintainer
source-build path, smoke checks, and troubleshooting.

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
for large in-memory payloads, prefer `select/2` or `stream/2`. For large files,
prefer the native path APIs below so the source is never loaded into a BEAM
binary.

Process a large file by path without `File.read/1`:

```elixir
{:ok, %{account_id: 7}} =
  SimdJson.select_file("account.json", account_id: ["account", "id"])

rows =
  SimdJson.stream_file("events.ndjson",
    format: :ndjson,
    fields: [id: ["id"], kind: ["kind"]],
    batch_size: 500,
    max_batch_bytes: 8_388_608
  )

Enum.take(rows, 10)
```

`open_file/1` and `select_file/2` use simdjson's padded memory-map owner.
`stream_file/2` additionally uses `ondemand::parser::iterate_many` with a
fixed 1 MiB parser window and one row/byte-bounded result batch per demand.
Its required `:format` is one of `:json_array`, `:ndjson`, `:json_sequence`,
or `:comma_delimited`. File streams operate only on top-level documents; they
do not accept a nested `:path`. Selected strings are copied, the source file
must remain immutable for the operation lifetime, and early halt immediately
closes the native cursor, parser, projection plan, and mapping.

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
`open_file/1`, `select/2`, `select_file/2`, `stream/2`, `stream_file/2`, and
`close/1`. There is no projection bang variant,
JSONPath, wildcard/filter/default policy, streaming cursor, ownership transfer,
raw native handle, or public diagnostic API. The active Milestone 4 runtime
routes native work through a bounded worker pool and non-blocking queue
configured at application startup. Saturation returns the existing redacted
`:busy` error; see the [pool operations guide](docs/milestones/04-worker-pool-and-operations.md#production-runbook).

Operational telemetry uses the standard `:telemetry` events
`[:simd_json, :job, :start | :stop | :exception | :cancelled]` and
`[:simd_json, :queue, :rejected]`. Metadata is limited to operation and outcome;
measurements contain bounded capacity, size, and duration values and never JSON
content, paths, PIDs, request references, or native addresses. Event fields and
capacity-planning guidance are documented in the
[telemetry runbook](docs/milestones/04-worker-pool-and-operations.md#telemetry).

Milestone 5 implements its safe Jason 1.4.5 compatibility subset through an
iterative native materializer and bounded-pool execution. The compatibility
surface intentionally excludes iodata, key atomization, structs, custom
decoders, decimal modes, and every non-empty option list. The supported
behavior, qualification boundary, and evidence contract are recorded in the
[Milestone 5 acceptance record](docs/milestones/05-compatible-decode-api-acceptance.md).

Stream a root or nested array lazily with a scalar projection:

```elixir
json = ~s({"orders":[{"sku":"ABC-123","total":19.95}]})

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

## Support and operational limits

Milestones 1–5 are active on the qualified Ubuntu 24.04 x86-64 target. Other
platforms remain experimental or unsupported until they pass the same package,
ABI, sanitizer, scheduler, lifecycle, benchmark, and shutdown gates. The exact
runtime, precompiled-NIF and optional source-build requirements, compatibility differences,
saturation behavior, and promotion criteria are in the
[support policy](docs/releases/support.md).

Binary APIs receive a complete resident JSON binary. File-backed APIs instead
pass only a path through the BEAM boundary: simdjson owns the memory map, and
`stream_file/2` parses bounded document windows while advising consumed Linux
mapping pages away at safe batch boundaries. `select_file/2` avoids the source
copy but may retain input-size-dependent simdjson structural indexes;
`stream_file/2` is the bounded-parser-memory path. `decode/1,2` still
materializes the complete result. Socket, device, iodata, and nested-path file
streaming are not supported. See the
[projection acceptance record](docs/milestones/02-projection-api-acceptance.md)
and [streaming acceptance record](docs/milestones/03-batched-array-streaming-acceptance.md).

Operations and accepted behavior are indexed in the
[milestone roadmap](docs/milestones/README.md). Compatibility details are in the
[decode guide](docs/milestones/05-compatible-decode-api.md) and
[decode acceptance record](docs/milestones/05-compatible-decode-api-acceptance.md).
Release changes and known limitations are recorded in the
[changelog](CHANGELOG.md). Report vulnerabilities privately according to the
[security policy](SECURITY.md).

## License

SimdJson wrapper code is available under the [MIT License](LICENSE).
The vendored simdjson source retains its upstream license choices and
attribution, described in [Third-Party Notices](THIRD_PARTY_NOTICES.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the supported development toolchain,
test tiers, SpecLed workflow, and native qualification commands. The ordinary
setup is:

```sh
mix deps.get
mix zig.get --version 0.16.0
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
