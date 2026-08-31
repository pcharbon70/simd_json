# Milestone 1 Native Foundation Acceptance Record

This record closes [Milestone 1](./01-native-foundation.md) only for the target
and boundaries listed below. The executable evidence is authoritative; this
document is its reviewable index.

## Acceptance status

**Status:** Accepted on the qualified target when the revision-keyed CI job is
green. The local immutable candidate below passed the complete gate; the CI
artifact records the final PR head on Ubuntu 24.04 before merge.

| Identity | Value |
| --- | --- |
| Local release-candidate revision | `63d1899c4f5ced158216c8dade4fed6b5574e411` |
| Local source tree | `20cd20e4d66c8605e435cabc1f28af1e8081aedc` |
| Qualification-input SHA-256 | `97ae50b15cf497538ad8dc6df9f7722b990d1a3f1140ac025b35498b287a2a80` |
| Qualification date | 2026-08-29 |
| Local observation host | Linux Mint 22.1, x86-64, kernel 6.8.0; compatibility evidence only, not an added supported target |
| Complete local command | `bash scripts/ci/qualify_milestone_1.sh` |
| CI workflow | [CI](https://github.com/pcharbon70/simd_json/actions/workflows/ci.yml) |
| CI artifact | `milestone-1-acceptance-<source revision>` |
| First accepted Ubuntu run | [Run 33250484580](https://github.com/pcharbon70/simd_json/actions/runs/33250484580), merge candidate `ecbc3a8b6a988f0295f3594d08b9457c488d889c`, artifact `milestone-1-acceptance-ecbc3a8b6a988f0295f3594d08b9457c488d889c` |

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
and runs this sequence without weakening any subject's executable threshold.
The formatter dependency is rebuilt first so a restored test-environment cache
cannot omit Zigler's generated Zig formatter plugin:

1. `mix deps.compile zigler --force`;
2. `mix format --check-formatted`;
3. `mix docs --warnings-as-errors`;
4. `MIX_ENV=test mix test --seed 0`;
5. `mix spec.next --base <base>`;
6. `mix spec.check --base <base>`;
7. `mix simd_json.verify_traceability`;
8. a canonical-state diff check and evidence checksum inventory.

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

The clean local run of `63d1899` produced these results:

| Gate | Result |
| --- | --- |
| Formatting and documentation | `mix format --check-formatted` passed; ExDoc generated HTML and EPUB with warnings treated as errors. |
| Full Elixir suite | 6 doctests and 68 tests passed with seed 0. |
| C ABI | Ordinary and ASan/UBSan profiles each passed the deterministic corpus plus 512 randomized cases with seed 260829001. |
| Zig ownership | Ordinary profile passed 10/10 tests. ASan/UBSan passed 9 tests with the documented concurrent-close case skipped because GCC's preloaded ASan cannot unmap Zig 0.16 custom thread stacks; the ordinary profile owns that race proof and the instrumented NIF exercises the threaded path. |
| Instrumented NIF | 30 threaded/public tests passed under ASan/UBSan. |
| Package and build | Required sources, headers, notices, and both licenses were present; generated native artifacts were absent; two network-disabled clean builds agreed and selected `haswell`. |
| Symbols | The standalone C ABI and NIF dynamic surfaces matched their allowlists; release test hooks and C++ implementation symbols were absent. |
| Local scheduler observation | 84 heartbeat samples; p50 3.011 ms, p95 5.252 ms, p99/max 17.185 ms; dirty CPU and dirty I/O utilization both 0%. |
| Accepted Ubuntu scheduler | Ubuntu 24.04.4, OTP 27.3.4.16/ERTS 15.2.7.12, 4 normal schedulers, virtualized AMD EPYC 7763; 65 samples; p50 3.761 ms, p95 16.084 ms, p99/max 50.804 ms; dirty CPU and dirty I/O utilization both 0%. Budgets were p95 50 ms, p99 250 ms, and max 500 ms. |
| Lifecycle | Seed 260829001; 20 caller deaths, 16 explicit documents, 16 GC documents, 8 exiting-owner documents, and 3 application cycles; every live native gauge returned to zero after each batch. |
| SpecLed | 68/68 Milestone 1 requirement/scenario claims had executed strength; 0 threshold failures, findings, warnings, uncovered policy files, or bootstrap exceptions. |

The revision-keyed CI artifact contains the accepted Ubuntu measurements and
verified checksums. Later accepted revisions must produce their own green
revision-keyed artifact; the recorded run is not transferable to changed
qualification inputs.

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

Milestone 1 acceptance itself did not add projection; Milestone 2 now governs
the separately accepted `select/2` slice. This record still does not add cursor
traversal, streaming, eager decode, ownership transfer, a raw resource
accessor, or a zero-copy input path. It also
does not claim a production capacity bound, fixed worker pool, backpressure,
overload policy, or production telemetry; those remain Milestone 4 work.
Repeated in-process shared-object unload is not supported by the qualified OTP
27.3 harness. Application stop/start generation isolation and full-VM NIF
load/unload are the accepted lifecycle boundaries.
