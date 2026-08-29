# Milestone 1 Native Foundation Acceptance Record

This record closes [Milestone 1](./01-native-foundation.md) only for the target
and boundaries listed below. The executable evidence is authoritative; this
document is its reviewable index.

## Acceptance status

**Status:** Pending the final clean, committed release-candidate run.

| Identity | Value |
| --- | --- |
| Local release-candidate revision | To be recorded after the clean committed run |
| Local source tree | To be recorded after the clean committed run |
| Qualification-input SHA-256 | To be recorded after the clean committed run |
| Qualification date | 2026-08-29 |
| Complete local command | `bash scripts/ci/qualify_milestone_1.sh` |
| CI workflow | [CI](https://github.com/pcharbon70/simd_json/actions/workflows/ci.yml) |
| CI artifact | `milestone-1-acceptance-<source revision>` |

The CI artifact's `acceptance/environment.txt`, each subject environment file,
and traceability inventory repeat the full source revision and source tree.
`SHA256SUMS` binds every retained evidence file except the checksum manifest
itself. This avoids treating a mutable branch name, a documentation checkbox,
or an earlier build as acceptance.

## Accepted target

| Operating system | Architecture and ABI | BEAM | Native toolchain | simdjson |
| --- | --- | --- | --- | --- |
| Ubuntu 24.04 LTS, glibc 2.39 | `x86_64-linux-gnu` | OTP 27.3, Elixir 1.18.4 | Zigler 0.16.0, Zig 0.16.0, bundled Clang/LLVM 21.1.0 and libc++ | Official v4.6.9; runtime dispatch `haswell`, `westmere`, or `fallback`; Ice Lake disabled |

Linux aarch64 and macOS remain experimental. Windows, BSD, musl, and all other
triples remain unsupported. None inherit the accepted target's ABI, sanitizer,
scheduler, or lifecycle claim.

## Executed matrix

The master command requires a clean committed worktree, records its revision,
and runs this sequence without weakening any subject's executable threshold:

1. `mix format --check-formatted`;
2. `mix docs --warnings-as-errors`;
3. `MIX_ENV=test mix test --seed 0`;
4. `mix spec.next --base <base>`;
5. `mix spec.check --base <base>`;
6. `mix simd_json.verify_traceability`;
7. a canonical-state diff check and evidence checksum inventory.

The SpecLed check executes the four owning subject commands:

- `bash scripts/ci/qualify_native_release.sh` — package inventory, provenance,
  pin and target guards, release compile/dispatch diagnostics, complete native
  tests, deterministic 512-case ABI stress, ordinary and ASan/UBSan C and Zig
  harnesses, the sanitizer-instrumented threaded/public NIF corpus, symbol
  allowlists, and two network-disabled clean builds;
- `bash scripts/ci/qualify_document_resource.sh` — ordinary and sanitizer Zig
  ownership plus resource, failure, close, GC, and baseline corpora;
- `bash scripts/ci/qualify_runtime.sh` — formal scheduler profile and seeded
  cancellation, teardown, application-generation, and memory-baseline stress;
- `bash scripts/ci/qualify_document_api.sh` — doctests, public valid/invalid
  corpora, errors, redaction, ownership, lifetime, scope enumeration, and
  release-symbol checks.

## Results

The final clean run must populate this section with its sanitizer summaries,
scheduler measurements, lifecycle baseline, full-suite result, and SpecLed
claim count before the status changes to accepted.

## Evidence layout

The `milestone-1-acceptance-<source revision>` CI artifact contains:

| Directory | Evidence |
| --- | --- |
| `acceptance/` | Revision, tree, input fingerprint, master commands/logs, canonical SpecLed state, and final summary. |
| `native/` | Package inventory, compiler/runtime details, ABI and randomized stress, sanitizer output, symbol checks, and offline-build diagnostics. |
| `document-resource/` | Zig profiles, focused ownership/lifecycle tests, and lifecycle JSON. |
| `runtime/` | Raw heartbeat samples, percentile/utilization summary, lifecycle seed/actions, and baseline snapshots. |
| `document-api/` | Public corpus, scope inventory, Elixir exports/types/docs, NIF symbols, and allowlists. |
| `traceability/` | Requirement/scenario-to-command/test inventory and executed-strength summary. |
| `SHA256SUMS` | Digest of every retained artifact file. |

## Remaining non-goals

Acceptance does not add projection, cursor traversal, streaming, eager decode,
ownership transfer, a raw resource accessor, or a zero-copy input path. It also
does not claim a production capacity bound, fixed worker pool, backpressure,
overload policy, or production telemetry; those remain Milestone 4 work.
Repeated in-process shared-object unload is not supported by the qualified OTP
27.3 harness. Application stop/start generation isolation and full-VM NIF
load/unload are the accepted lifecycle boundaries.
