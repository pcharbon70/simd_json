# Milestone 2 Projection Runtime Qualification

This record fixes the repeatable scheduler and lifetime methodology used to
activate `simd_json.projection_execution`. It supplements the Milestone 1
runtime qualification; it does not change the supported target or turn the
current Zigler-threaded adapter into a production worker pool.

## Scheduler profile

The formal profile runs on the qualified Ubuntu 24.04 x86-64 target and records
the exact OTP, ERTS, Elixir, CPU, scheduler counts, source revision and tree,
fixture digest, path topology, concurrency, rounds, and raw heartbeat samples.
It uses one independent 2 ms heartbeat while public binary and document
`SimdJson.select/2` calls process a 4 MiB sparse object. Successful, malformed,
missing-field, incorrect-type, and caller-cancelled work are represented.

Percentiles use nearest rank. Qualification requires at least 40 samples,
p95 no greater than 50 ms, p99 no greater than 250 ms, and no sample greater
than 500 ms. Dirty CPU and dirty I/O utilization must each remain below 25
percent. Test-only admission and native worker counters must both increase by
exactly the number of attempted selections. The checked-in Zigler declaration
is separately inspected to prove the projection entry is `:threaded` and that
no ordinary or dirty fallback is registered.

The exact command is:

```sh
bash scripts/ci/qualify_projection_runtime.sh
```

When `SIMD_JSON_QUALIFICATION_DIR` is set, raw evidence is written to
`projection-scheduler.json`, including heartbeat intervals, scheduler wall
time, budgets, fixture identity, native baseline/final snapshots, and worker
accounting.

## Lifecycle profile

The default deterministic seed is `260831006`; override it with
`SIMD_JSON_LIFECYCLE_SEED` to replay another positive seed. The seed orders the
cartesian matrix of binary/document sources and all six projection cancellation
boundaries. The suite additionally executes every operation/conversion failure
checkpoint, pre-worker rejection and retry, owner/non-owner access, fresh to
selecting/consumed/closing/closed document transitions, repeated close,
dropped result and document GC, cleanup callback retry, and application
stop/start generation isolation.

Every batch waits at most ten seconds for the coordinator and all exposed live
native gauges to return to their captured baseline. The C ABI sanitizer suite
independently reads plan/node/key-byte accounting, while the runtime snapshot
records operations, retained sources/documents, plans, slots, private term
environments, temporary document graphs, dispatcher work, and failed cleanup
handoffs. Neither source values nor caller paths appear in the evidence.

`projection-lifecycle.json` records the seed, ordered cancellation cases,
failure matrix, generations, fixture digest, baseline/final snapshots, command,
and source identity. Application restart exercises supported callback and
generation behavior only. Repeated in-process shared-object unload remains
unsupported because no real OS-loader harness exists.

## Interpretation

The scheduler thresholds are engineering regression budgets for the supported
CI target, not universal latency guarantees. A passing lifecycle run proves
bounded recovery for the tested process and application transitions. It does
not claim worker-pool admission, backpressure, telemetry, or repeated shared
library unloading; those remain deferred or unsupported as documented.
