# Milestone 3 Batched Array Streaming Acceptance Record

**Status:** Accepted on the qualified Ubuntu 24.04 x86-64 target when the
revision-bound Milestone 3 CI gate is green. This library remains
pre-production pending Milestone 4 global admission control.

| Identity | Value |
| --- | --- |
| Qualification date | 2026-09-02 |
| Qualification seed | `260902003` |
| Private ABI | v3, retaining ABI v1/v2 symbols |
| Parser | vendored simdjson 4.6.9 |
| Benchmark baseline | Jason 1.4.5 |
| Complete command | `bash scripts/ci/qualify_milestone_3.sh` |
| CI artifact | `milestone-3-acceptance-<source revision>` |

The committed corpus contains root and nested 100-row, 10,000-row, and
1,000,000-row fixtures plus a huge-row boundary case. The million-row source is
45,666,793 bytes with SHA-256
`2171d30d6e247aede4318ba732e60e41af513be04b3d148cd26b92f218042ea7`.
Compressed fixture storage is outside the timed region.

The development-host candidate passed both frozen memory thresholds: the
million-row stream process peak remained below 128 MiB and below 60 percent of
Jason full decode plus equivalent lookup/reduction. Raw evidence records first
row, total p50/p95/p99 latency, rows/second, process and RSS peaks, reductions,
GC counts, fixture and policy identities, native baseline recovery, and both
batch sizes. Latency and throughput are contextual, not universal superiority
claims.

The runtime profile uses independent 2 ms heartbeats and requires p95 ≤ 50 ms,
p99 ≤ 250 ms, maximum ≤ 500 ms, and dirty CPU/I/O utilization below 25 percent.
It records raw intervals, scheduler wall time, exact worker entries, unreduced
zero-setup, within/between-batch suspension, mailbox stability, application
cycles, cancellation, and all live native gauges returning to baseline.

The CI evidence bundle contains `native/`, `stream-execution/runtime/`,
`stream-execution/benchmark/`, `traceability/`, canonical SpecLed state, and a
top-level `SHA256SUMS`. The final source revision, tree, fingerprint, workflow
run, artifact digest, and accepted measurements are supplied by that immutable
artifact; local results are compatibility evidence only.

Acceptance excludes raw cursors/batches, prefetch, transfer, checkpoint/resume,
parallel array work, eager decode, global worker admission, production queue
fairness, telemetry, and repeated shared-object unload.
