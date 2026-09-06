# Milestone 6 CI Failure Reproduction

Date: 2026-09-05

This record preserves the Phase 2 entry failures without treating a passing
seed, a warm developer build, or a retried GitHub job as release evidence.

## Qualified environment

- GitHub runner: Ubuntu 24.04, x86-64
- OTP: 27.3
- Elixir: 1.18.4
- Mix environment: `test`
- Zigler release mode: `safe`
- Zig: 0.16.0 from the Zigler cache path
- Cache identity: runner OS, architecture, Mix environment, Zigler release
  mode, `.tool-versions`, `mix.exs`, `mix.lock`, Elixir native wrappers, and
  `native/**`

## Formatter bootstrap failure

The Milestone 5 aggregate qualifier calls `mix format --check-formatted`
without first compiling the pinned Zigler formatter plugin. Earlier milestone
qualifiers explicitly run `mix deps.compile zigler --force`, proving that the
Milestone 5 command order lost an established prerequisite. A warm local build
can hide this because `Elixir.Zig.Formatter` and its NIF already exist.

The deterministic regression contract is therefore structural: install Zig
first, compile Zigler in the same explicit `MIX_ENV` and canonical build path,
then run formatting. Both an empty build/cache path and a restored path must
execute that same bootstrap order.

## Sanitizer VM abort

Pull request 38 CI run `33985428541` failed in
`scripts/native/run_nif_sanitizer_tests.sh`. The isolated test VM reported
ExUnit seed `935088`, then aborted with exit 134 at
`ethr_mutex_lock(): Invalid argument (22)`.

Local reproduction used the same ASan/UBSan preload, isolated build path,
scheduler flags, test corpus, and seed:

```text
SIMD_JSON_NIF_SANITIZER_SEED=935088 \
  bash scripts/native/run_nif_sanitizer_tests.sh
```

The no-trace run reproduced exit 134. The same seed with
`SIMD_JSON_NIF_SANITIZER_TRACE=1` passed all 75 tests because trace mode
serializes and slows the lifecycle boundary. A random local sanitizer seed
`878023` also passed. This makes the failure timing-sensitive while the fixed
seed keeps the triggering order reviewable.

## Native baseline race

The merged-main CI run `33986146760` reached the ordinary native corpus with
seed `661703`. `DecodePoolLifecycleTest` recorded two live operations as its
baseline, then failed after those previous operations drained to zero. Its
quiescence helper waited only for the Elixir coordinator and did not wait for
native operation, document, or retained-input gauges. The regression must
require a zero native baseline before replacing or stopping the shared pool.

## Required closure

Phase 2 closes these findings only when:

1. sanitizer seed `935088` passes without trace in an isolated build;
2. repeated native and full-suite seeds start and finish at zero live gauges;
3. formatter bootstrap passes with empty and restored build/cache paths; and
4. pull-request and merged-main GitHub runs pass with the same qualification
   input identity.
