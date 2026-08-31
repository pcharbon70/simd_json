# Milestone 2 Projection API Acceptance Record

This record closes [Milestone 2](./02-projection-api.md) only for the target and
boundaries below. Executable revision-keyed evidence is authoritative; this
document is its reviewable index.

## Acceptance status

**Status:** Accepted on the qualified target when the revision-keyed Milestone
2 CI job is green. The development-host benchmark candidate passed the frozen
allocation threshold; the PR artifact records the final Ubuntu 24.04 source
revision, tree, commands, raw measurements, and checksums before merge.

| Identity | Value |
| --- | --- |
| Frozen fixture/benchmark revision | `17134574ff0a2d9bf6012d6d36dbbeead28159a2` |
| Frozen fixture/benchmark source tree | `4649c558e7a62183c457f65a2df8fcbea67deaa0` |
| Qualification date | 2026-08-31 |
| Qualification seed | `260831006` |
| Fixture manifest SHA-256 | `e06fac9f8aa4861718247cd4ef55f25b3a1637eb7af740ea55d2ff40b3d89f28` |
| Complete command | `bash scripts/ci/qualify_milestone_2.sh` |
| CI workflow | [CI](https://github.com/pcharbon70/simd_json/actions/workflows/ci.yml) |
| CI artifact | `milestone-2-acceptance-<source revision>` |
| First accepted Ubuntu run | [Run 33389459172, attempt 2](https://github.com/pcharbon70/simd_json/actions/runs/33389459172/attempts/2), PR head `6d63cab041f565be1b06ac6bc170855e1df50263`, checked-out merge candidate `89e75453f43e64850d8b39a37869f321e5fbf32d`, source tree `a5168c7cc45661f25cb8ef548e09ac7ce6b81ef6` |
| Accepted artifact | `milestone-2-acceptance-89e75453f43e64850d8b39a37869f321e5fbf32d`, artifact ID `9758339542`, 93,239 bytes, GitHub archive SHA-256 `0fac7246f96c18129914ba335b866e4585321c6506478e883661a4a5ca965a27` |
| Accepted Ubuntu result | 127 Milestone 1 and 2 claims executed; sparse projection allocation threshold passed; 42 heartbeat samples with p95 42.998 ms and p99/maximum 54.404 ms |

The CI artifact's `acceptance/environment.txt`, each subject environment file,
and traceability inventory repeat the full source revision, tree, and
qualification-input SHA-256. Its top-level `SHA256SUMS` binds every retained
evidence file except that checksum manifest. A branch name, local result, plan
checkbox, or older artifact is not transferable to changed inputs.

## Accepted target and dependencies

| Component | Accepted value |
| --- | --- |
| Operating system and ABI | Ubuntu 24.04 LTS, glibc 2.39, `x86_64-linux-gnu` |
| BEAM | OTP 27.3, Elixir 1.18.4 |
| Native toolchain | Zigler 0.16.0; Zig 0.16.0; bundled Clang/LLVM 21.1.0 and libc++ |
| Parser | Official vendored simdjson 4.6.9; runtime dispatch `haswell`, `westmere`, or `fallback`; Ice Lake disabled |
| Benchmark baseline | Jason 1.4.5, exact development/test-only dependency |
| Private ABI | Version 2 with the four ABI v1 parser/document symbols retained |

No other platform inherits acceptance. The current threaded adapter remains
pre-production despite passing scheduler qualification.

## Executed matrix

The clean-worktree master gate records revision and environment, then runs:

1. vendored-source and qualification-fingerprint verification;
2. the unpacked Hex inventory and network-disabled ABI v2 source compile;
3. ordinary and ASan/UBSan C/Zig plan, traversal, ownership, and failure tests;
4. the sanitizer-instrumented threaded and public projection corpus;
5. production-mode ABI/NIF symbol and diagnostic-string inspection;
6. public grammar, result, error, ownership, atom, redaction, and surface tests;
7. formal projection heartbeat and seeded lifecycle profiles;
8. the frozen Jason end-to-end sparse allocation comparison;
9. all Milestone 1 qualification commands and the complete Elixir suite;
10. formatting, ExDoc warnings-as-errors, SpecLed execution/validation, canonical
    state, and requirement/scenario traceability.

Subject commands are:

```sh
bash scripts/ci/qualify_native_release.sh
bash scripts/ci/qualify_document_resource.sh
bash scripts/ci/qualify_runtime.sh
bash scripts/ci/qualify_document_api.sh
bash scripts/ci/qualify_projection_execution.sh
```

The projection execution command composes the formal runtime and benchmark
commands. All seven Milestone 1 and Milestone 2 subjects must be active, have
executed verification, and retain no exception.

## Frozen fixtures and threshold

| Fixture | Bytes | SHA-256 |
| --- | ---: | --- |
| small | 16,384 | `58ae5aae554dc5246d591e5ed03c12f1a96d8b96a792f365d0055555e035e156` |
| medium | 524,288 | `54c9936cfe9d08fe4049613d4a4acef50e43dd6e3fa208eed6cf14002cd8d8d8` |
| large | 4,194,304 | `850a2752ae9e961f1cf9e79d1fb53f97f467fb7a6913d9ca3587cabbc71dbc80` |

Each fixture contains five selected scalars and large unselected nested object,
array, string, numeric, and boolean content. The frozen policy uses three
warm-ups and fifteen fresh-process samples per workflow/fixture, alternating
order, full-sweep isolation, one-millisecond peak sampling, nearest-rank
percentiles, and retained equivalent result maps.

Acceptance requires the median estimated caller BEAM allocated bytes for
`SimdJson.select/2` to be no more than 30 percent of Jason full decode plus
lookups on both medium and large fixtures. This is at least a 70 percent sparse
allocation reduction. Latency and throughput are measured context only.

## Development-host candidate result

The frozen revision above was observed on Linux Mint 22.1 x86-64, OTP
27/ERTS 15.2.3, Elixir 1.18.4, and an Intel i7-12700F. It is compatibility and
pre-CI evidence, not an added supported target.

| Fixture | Workflow | p50 latency | Median estimated BEAM allocation | Allocation result |
| --- | --- | ---: | ---: | --- |
| small | `SimdJson.select/2` | 1.584 ms | 4,256 bytes | Context only |
| small | Jason decode + lookup | 1.301 ms | 217,800 bytes | Context only |
| medium | `SimdJson.select/2` | 6.877 ms | 4,256 bytes | 99.938% below Jason |
| medium | Jason decode + lookup | 16.771 ms | 6,908,488 bytes | Baseline |
| large | `SimdJson.select/2` | 24.251 ms | 4,256 bytes | 99.992% below Jason |
| large | Jason decode + lookup | 121.237 ms | 54,479,720 bytes | Baseline |

The raw JSON also records p95/p99/min/max latency, p50 throughput, process,
binary, and RSS peaks, native peak/baseline/final snapshots, retained source
references, GC count/time, reductions, scheduler utilization, policy, and every
individual sample. The allocation estimate is GC-reclaimed caller words plus
the post-fullsweep retained live-word delta. Separate peak and native metrics
make that deliberately scoped estimate reviewable.

## Scheduler and lifetime criteria

The formal projection profile uses a 4 MiB sparse source, public binary and
document success, malformed, missing, wrong-type, and caller-cancelled cases,
forty rounds per caller, a two-millisecond heartbeat, and exact admission and
native worker counts. It requires at least 40 samples, p95 no greater than
50 ms, p99 no greater than 250 ms, maximum no greater than 500 ms, and dirty
CPU/I/O utilization below 25 percent.

The seeded lifecycle profile orders every binary/document combination across
the six projection boundaries. It also covers every reachable failure
checkpoint, submission rollback and retry, fresh/selecting/consumed/closing/
closed documents, owner checks, repeated close, copied/dropped results, GC
cleanup retry, and application generation change. Every batch must return all
live operation, source, document, plan, slot, term-environment, temporary graph,
dispatcher, and failed-handoff gauges to baseline within ten seconds. C ABI
accounting independently proves node and copied key-byte recovery.

## Evidence layout

| Directory | Evidence |
| --- | --- |
| `acceptance/` | Revision, tree, fingerprint, master logs, canonical SpecLed state, traceability summary. |
| `native/` | Package inventory, offline compile, ABI tests, sanitizers, release symbols, provenance and target guards. |
| `document-resource/`, `runtime/`, `document-api/` | All inherited Milestone 1 regression evidence. |
| `projection-execution/runtime/` | Raw heartbeat JSON, scheduler wall time, lifecycle seed/cases/generations and baseline snapshots. |
| `projection-execution/benchmark/` | Frozen policy identity, raw benchmark JSON/Markdown, all samples and allocation decision. |
| `traceability/` | Seven active subject inventories with claim-to-command/test mappings and executed strength. |
| `SHA256SUMS` | Digest of every retained evidence file. |

## Limitations and non-goals

Acceptance does not claim universal speed superiority, zero-copy input or
results, reusable compiled plans, JSONPath, wildcards, filters, defaults,
optional fields, container materialization, eager decode, streaming, public
cursors, ownership transfer, public cancellation, diagnostics, production
worker-pool capacity, backpressure, or telemetry. Those are deferred.

Repeated in-process shared-object unload remains unsupported because no real
loader harness exists. Application stop/start proves cancellation, callback,
and generation isolation only. Any changed source, fixture, threshold,
dependency, target, ABI, or qualification command requires a new
revision-keyed artifact.
