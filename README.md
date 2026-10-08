# SimdJson

`SimdJson` is an Elixir library for decoding JSON and extracting selected
values with SIMD-accelerated parsing. Its file-backed APIs keep large JSON
sources out of BEAM binaries and delegate mapping, parsing, and batching to
simdjson.

## Choose SimdJson for selective work

`SimdJson` is most useful when you need only part of a large JSON document. In
the checked-in one-million-row wide-document benchmark, selecting 1 to 16
fields from one row was **7.59× to 8.05× faster** than fully decoding the same
document with Jason and then performing equivalent lookups. The measured
incremental worker-process memory peak (not total VM memory) rounded to 0 to 0.02 MiB
for `SimdJson.select/2`, compared with about 1,608 MiB for Jason.

That is a sparse-projection result, not a claim that every SimdJson operation
is faster. If you need a complete Elixir representation of an ordinary JSON
document, Jason is generally the better choice: the checked-in eager-decode
benchmark shows it is faster for most tested inputs.

For row-oriented large files, `SimdJson.stream_file/2` prioritizes bounded
batch memory and early delivery. In the related million-row binary-stream
benchmark—which measures `stream/2`, not `stream_file/2`—the batch-size-1,000
SimdJson workflow took 1.87× as long overall as Jason, but used 40% of Jason's
worker-process memory peak, about 48% of its whole-VM RSS peak, and delivered the first
row about 40× sooner. See the
[benchmark reports](docs/benchmarks/README.md) for workload definitions, raw
measurements, and interpretation limits.

## Installation

Add `simd_json` to your dependencies:

```elixir
def deps do
  [
    {:simd_json, "~> 1.0.0"}
  ]
end
```

Then fetch and compile:

```sh
mix deps.get
mix compile
```

On Ubuntu 24.04 x86-64, compilation downloads and verifies the versioned NIF.
Ordinary package consumers do not need Zig, Zigler, a C++ compiler, or a system
simdjson installation. See the [deployment guide](docs/guides/06-deployment.md)
for supported environments, offline installs, and the optional source build.

## Quick examples

Decode a complete JSON value:

```elixir
SimdJson.decode(~s({"ready":true,"items":[1,2,3]}))
# => {:ok, %{"ready" => true, "items" => [1, 2, 3]}}
```

Extract only the scalar fields you need:

```elixir
json = ~s({"customer":{"id":1234,"name":"Acme"}})

SimdJson.select(json,
  id: ["customer", "id"],
  name: ["customer", "name"]
)
# => {:ok, %{id: 1234, name: "Acme"}}
```

Stream projected rows from a large file without calling `File.read/1`:

```elixir
rows =
  SimdJson.stream_file("events.ndjson",
    format: :ndjson,
    fields: [id: ["id"], kind: ["kind"]],
    batch_size: 500,
    max_batch_bytes: 8_388_608
  )

Enum.take(rows, 10)
```

## Guides

1. [01 — Getting Started](docs/guides/01-getting-started.md)
2. [02 — Decoding JSON](docs/guides/02-decoding-json.md)
3. [03 — Selecting Fields](docs/guides/03-selecting-fields.md)
4. [04 — Streaming Large Files](docs/guides/04-streaming-large-files.md)
5. [05 — Errors, Limits, and Performance](docs/guides/05-errors-limits-performance.md)
6. [06 — Deployment and Native Delivery](docs/guides/06-deployment.md)
7. [07 — Explore with Livebook](docs/guides/07-explore-with-livebook.livemd)
- [Benchmark reports](docs/benchmarks/README.md)

The public API consists of `decode/1,2`, `decode!/1,2`, `open/1`,
`open_file/1`, `select/2`, `select_file/2`, `stream/2`, `stream_file/2`, and
`close/1`.

## Support

The qualified target is Ubuntu 24.04 x86-64. Other platforms are experimental
or unsupported until they pass the same package, ABI, sanitizer, scheduler,
lifecycle, benchmark, and shutdown checks.

Native work uses a fixed bounded worker pool. A full queue returns the
redacted `:busy` error instead of falling back to scheduler-blocking work.

Binary APIs receive a complete resident JSON binary. File-backed APIs pass only
a path through the BEAM boundary. `select_file/2` avoids copying the source into
a BEAM binary but may retain input-size-dependent simdjson structural indexes.
`stream_file/2` is the bounded-parser-memory path and returns row- and
byte-bounded result batches on demand. Eager decoding still materializes the
complete Elixir value.

See [Errors, limits, and performance](docs/guides/05-errors-limits-performance.md)
for the complete boundary and [SECURITY.md](SECURITY.md) for private security
reporting.

## License

The Elixir wrapper is available under the [MIT License](LICENSE). Vendored
simdjson retains its upstream license choices and attribution; see
[Third-Party Notices](THIRD_PARTY_NOTICES.md).
