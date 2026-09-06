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

## Post-merge request-resource reproduction

PR 39 passed its cold and restored checks, but the first merged-main run
`34030167900` aborted its cold job after `phase6_scheduler` with the same
`ethr_mutex_lock(): Invalid argument (22)` signature. Its restored job passed
the identical source tree and qualification fingerprint.

A focused `--repeat-until-failure 50` run over pool retirement, application
stop/start, lifecycle, scheduler, projection, and selection tests reproduced
exit 134 locally after roughly 35 iterations and 548 application generations.
Review of the terminal-delivery path found that each job retained the native
request control block while the corresponding monitored BEAM resource object
could be garbage-collected. The worker subsequently passed that retired object
to `enif_demonitor_process`.

A core dump placed the failing worker in `enif_demonitor_process`, reached from
`RequestControl.demonitor` after result delivery and before the pool recorded
the terminal job counters. The repair removes resource-object demonitoring from
the worker path. The job-owned control block still survives through delivery
and terminal cleanup, while ERTS automatically removes the monitor when it
deallocates the request resource. Explicit fixture demonitoring remains limited
to a NIF invocation that receives the live request resource as an argument. A
paused-worker regression deliberately drops the Elixir request term and forces
garbage collection before allowing delivery to finish. With a forced test NIF
rebuild, that regression passed 200 consecutive runs. The broader 27-test
lifecycle, application restart, scheduler, projection, and selection corpus
then passed 50 consecutive cycles (1,350 tests), reaching application
generation 716 without another VM abort.
