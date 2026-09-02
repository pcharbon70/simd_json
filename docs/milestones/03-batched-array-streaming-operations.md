# Milestone 3 Batched Array Streaming Operations

Milestone 3 is supported on Ubuntu 24.04 x86-64 GNU/Linux with OTP 27.3,
Elixir 1.18.4, Zig/Zigler 0.16.0, vendored simdjson 4.6.9, and private ABI v3.
Other targets do not inherit its package, sanitizer, scheduler, or benchmark
evidence. The threaded adapter remains pre-production until Milestone 4 adds a
bounded global worker pool and admission policy.

`SimdJson.stream/2` requires `:path` and `:fields`. `:batch_size` defaults to
1,000 (range 1–10,000); `:max_batch_bytes` defaults to 8 MiB (range 1–64 MiB).
Use `[]` for a root array or binary keys and unsigned indexes for a nested
target. Fields use the Milestone 2 scalar projection grammar. Construction is
lazy, enumeration is owner-bound, binary sources are replayable, and document
sources commit one-shot consumption when cursor access begins.

One native batch is requested at a time. Smaller batches improve cancellation
latency and reduce returned-row memory; larger batches amortize worker and NIF
boundaries. A row larger than the byte limit raises `:batch_too_large` with its
source index. Parse, path, projection, ownership, cancellation, and lifecycle
failures raise redacted `SimdJson.Error` values after cursor cleanup. Early
halt does not validate the unconsumed remainder.

Run the focused gates with:

```sh
bash scripts/ci/qualify_native_release.sh
bash scripts/ci/qualify_stream_runtime.sh
bash scripts/ci/qualify_stream_benchmark.sh
bash scripts/ci/qualify_stream_execution.sh
```

Regenerate the frozen compressed fixtures with:

```sh
elixir scripts/benchmarks/generate_stream_fixtures.exs
git diff -- bench/stream_fixtures
```

For failures, inspect package inventory and symbol logs first, then raw
scheduler/demand/lifecycle JSON, then the benchmark report. Replay the recorded
seed and fixture digest. ABI, dependency, fixture, policy, limit, or target
changes invalidate the acceptance record and require the full matrix again.

No public batch API, raw cursor, prefetch, transfer, checkpoint/resume, parallel
array traversal, eager decode, global admission control, or telemetry is
provided. Application restart is qualified; repeated in-process shared-object
unload is unsupported.
