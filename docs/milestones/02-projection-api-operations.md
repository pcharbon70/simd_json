# Milestone 2 Projection API Operations

This guide is the maintenance companion to
[Milestone 2](./02-projection-api.md). The accepted ADRs and active Projection
API, Engine, and Execution specifications remain normative; this document
explains how to build, exercise, benchmark, and troubleshoot the implemented
slice.

## Support and runtime boundary

Milestone 2 is supported on the same qualified target as Milestone 1: Ubuntu
24.04 LTS, x86-64 GNU/Linux with glibc 2.39, OTP 27.3, Elixir 1.18.4, Zigler
0.16.0, Zig 0.16.0, and vendored simdjson 4.6.9. Other targets do not inherit
its ABI, sanitizer, scheduler, lifecycle, or allocation evidence.

The present Zigler-threaded adapter remains a pre-production qualification
runtime. It does not provide a bounded production worker pool, admission queue,
backpressure, overload policy, or public telemetry. Those controls remain
Milestone 4 work.

## Public grammar and results

`SimdJson.select/2` accepts a JSON binary or a genuine fresh document owned by
the caller. Its projection is a non-empty proper list of `{output_key, path}`
pairs:

```elixir
projection = [
  {:id, ["customer", "id"]},
  {"name", ["customer", "name"]},
  {:sku, ["orders", 0, "sku"]}
]

{:ok, result} = SimdJson.select(json, projection)
```

- output keys are existing atoms or binaries and must be unique;
- each path is a non-empty proper list;
- binary path segments are valid UTF-8 object keys;
- integer segments are array indexes from zero through `UINT64_MAX`;
- duplicate complete paths are allowed and share one native terminal;
- maps, empty/improper lists, duplicate output keys, invalid UTF-8, negative or
  oversized indexes, and every other segment type return
  `:invalid_projection` before native admission.

The result contains only selected strings, integers, finite floats, booleans,
and `nil`. Object or array terminals return `:incorrect_type`. Selected strings
are copied, arbitrary JSON keys are never atomized, and any failure returns one
error with no partial map. A path attached to an error is copied only from the
validated caller projection.

## Traversal and duplicate keys

All paths compile into one private operation-scoped prefix-sharing plan. The
engine follows JSON document order, evaluates common prefixes and identical
paths once, and restores caller output keys from fixed slots. It structurally
consumes the complete source, including unselected content and content after
the last selected value. A malformed unselected subtree therefore fails the
operation.

When an object repeats a requested key, the first occurrence in document order
provides the selected value. Later occurrences are still consumed for complete
validation but do not overwrite the slot. Projection declaration order does not
change that rule.

## Binary and document lifetimes

Binary selection creates an unpublished padded input, parser, document, plan,
slot set, and private term environment inside one correlated threaded
operation. It destroys that native graph before returning.

A document is single-owner and one-shot. Complete projection validation and a
proven pre-worker submission rejection leave it fresh. Immediately before
native cursor access, its reservation commits; success and operational failure
then both leave it consumed. A consumed document can still be closed, and
owner close remains idempotent. Non-owner selection returns `:not_owner`
without revealing lifecycle state. Close cancels an active selection, waits for
its reservation to end, and performs cleanup once.

## Development commands

Install dependencies, compile, and run the complete suite:

```sh
mix deps.get
mix compile --force
mix test --seed 0
```

Focused public, native, and runtime gates are:

```sh
bash scripts/ci/qualify_document_api.sh
bash scripts/ci/qualify_native_release.sh
bash scripts/ci/qualify_projection_runtime.sh
bash scripts/ci/qualify_projection_benchmark.sh
```

The complete clean-worktree acceptance command is:

```sh
bash scripts/ci/qualify_milestone_2.sh
```

The native release gate builds and inspects the Hex archive, performs a
network-disabled compile from its unpacked source, runs ordinary and
ASan/UBSan C and Zig matrices, runs the sanitizer-instrumented public NIF
corpus, checks provenance and target guards, and inspects the production-mode
symbol/string surface. The runtime gate writes raw heartbeat and lifecycle
JSON when `SIMD_JSON_QUALIFICATION_DIR` is set.

## Sparse benchmark

Jason 1.4.5 is pinned directly for development and test only. The frozen
policy is `bench/sparse_projection_policy.exs`; the manifest and 16 KiB,
512 KiB, and 4 MiB fixtures are in `bench/fixtures`. The accepted comparison is
the complete binary `SimdJson.select/2` workflow versus `Jason.decode!/1` plus
equivalent lookups and the same retained result map.

The policy uses three warm-ups and fifteen fresh-process samples per workflow
and fixture, alternates workflow order, performs a full sweep before each
sample, and uses nearest-rank percentiles. It records raw latency, throughput,
estimated caller BEAM allocation, process/binary/RSS peaks, native gauge peaks,
retained result binary size, GC count/time, reductions, and scheduler
utilization. Medium and large fixtures pass only when median estimated
`select/2` BEAM allocation is at most 30 percent of Jason's—a predeclared
minimum reduction of 70 percent. Latency and throughput are context, not a
universal superiority claim.

Regenerate the fixtures deterministically and verify that only the intended
generator/digest change occurs:

```sh
elixir scripts/benchmarks/generate_sparse_fixtures.exs
git diff -- bench/fixtures
mix test test/benchmark/sparse_fixture_test.exs --seed 0
```

Never change fixture shape, sizes, sample counts, or the allocation threshold
after observing a candidate result. Change and review the policy first, commit
it, then take a new revision-keyed measurement.

## Dependency and ABI upgrades

For a Jason upgrade, change the exact development/test requirement and lock as
one reviewed change, regenerate no fixture unless its deterministic format
really changes, and rerun the fixture, public, benchmark, and complete gates.
The benchmark remains a comparison of equivalent workflows, not parser
kernels.

For simdjson, Zig, Zigler, Elixir, OTP, compiler, flag, ABI, target, or vendored
source changes, follow the Milestone 1 provenance procedure and update
`native/manifest.exs`. Recompute the qualification fingerprint only after the
entire ABI v2 package, sanitizer, runtime, benchmark, SpecLed, and regression
matrix passes. A changed pin invalidates the old supported-target evidence.

## Failure triage

Use the first failing layer; do not bypass it with a fallback parser or
scheduler:

| Failure | First checks |
| --- | --- |
| Package or offline compile | Compare `package-contents.txt`, required inputs, vendored files, `.tool-versions`, lock data, and `native/manifest.exs`. |
| C/Zig sanitizer | Replay the recorded seed and profile; inspect the first ASan/UBSan report and the owning plan/slot/document rollback path. |
| Release symbols or strings | Build with `MIX_ENV=prod`; confirm test NIF registration remains compile-time gated and the allowlists are unchanged intentionally. |
| Scheduler percentile | Confirm fixture digest, scheduler counts, host load, raw intervals, worker/admission deltas, and lack of dirty/ordinary fallback. |
| Lifecycle baseline | Replay `SIMD_JSON_LIFECYCLE_SEED`; identify the first boundary/batch and compare every live gauge plus coordinator requests. |
| Benchmark threshold | Confirm fixture and policy digests, exact Jason pin, equivalent result, isolated sample order, and raw allocation values. Do not tune the accepted threshold from the failure. |
| SpecLed | Regenerate state, inspect missing covers/commands/exceptions, and run the exact base reported by `mix spec.next`. |

Evidence and public errors deliberately omit source bytes, caller path contents,
native addresses, exception text, and raw handles. Preserve that redaction when
adding diagnostics.

## Deferred and unsupported behavior

Milestone 2 does not expose reusable compiled plans, eager decode, JSONPath,
wildcards, filters, defaults, optional fields, container materialization,
streaming, cursor access, ownership transfer, public cancellation, or public
diagnostics. Repeated in-process shared-object unload is unsupported; an
application stop/start proves generation and callback behavior, not OS-loader
unload. Any new surface or lifetime rule requires a superseding decision and
new qualification evidence.
