# Milestone 4 Worker Pool Implementation Plan

<!-- covers: simd_json.package.documentation_layout -->

This plan replaces the qualification-only Zigler threaded bridge with one
fixed-capacity native execution subsystem. It preserves all Milestone 1–3
ownership and API contracts while adding bounded global admission,
cooperative cancellation, resource serialization, redacted telemetry, and
deterministic worker lifecycle.

## Source Authority

1. [Milestone 4 — Worker Pool, Cancellation, Backpressure, and Telemetry](../../../docs/milestones/04-worker-pool-and-operations.md)
2. [Bounded Native Pool Configuration and Admission](../../decisions/0010-bounded-native-pool-configuration-and-admission.md)
3. [Native Worker Pool and Admission](../../specs/native_pool.spec.md)
4. Active Milestone 1–3 decisions and specifications.

## Phase Order

1. [Phase 1 — Configuration and Admission Contract](./phase-01-configuration-and-admission-contract.md)
2. [Phase 2 — Native Pool State and Fixed Workers](./phase-02-native-pool-state-and-fixed-workers.md)
3. [Phase 3 — Owned Jobs and Non-blocking Queue](./phase-03-owned-jobs-and-nonblocking-queue.md)
4. [Phase 4 — Cancellation, Delivery, and Resource Serialization](./phase-04-cancellation-delivery-and-resource-serialization.md)
5. [Phase 5 — Telemetry, Public Operations, and Lifecycle](./phase-05-telemetry-public-operations-and-lifecycle.md)
6. [Phase 6 — Saturation Qualification and Activation](./phase-06-saturation-qualification-and-activation.md)

Phase 1 publishes no pool controls and does not claim production execution.
Each later phase must preserve the earlier release ABI, scheduler, ownership,
projection, streaming, memory, and sanitizer gates.

## Contract Ownership by Phase

| Phase | Primary responsibility |
| --- | --- |
| 1 | Closed configuration, bounds, startup preflight, busy reason, redacted snapshot, and planning baseline. |
| 2 | Shared native pool state, fixed worker startup, partial-start rollback, and worker join primitives. |
| 3 | Owned job descriptors, FIFO queue, exact capacity accounting, immediate rejection, and resource retention. |
| 4 | Caller monitoring, cooperative cancellation, unique delivery, close races, and per-resource serialization. |
| 5 | Route open/select/stream jobs through the pool, emit redacted telemetry, and implement application/unload lifecycle. |
| 6 | Saturation, fairness, latency, memory, race/sanitizer qualification, operations docs, and spec activation. |

## Shared Conventions

- Checklist numbering uses phase `N`, section `N.M`, task `N.M.K`, and subtask `N.M.K.L`.
- A checkbox closes only with real implementation and executable evidence.
- Ordinary NIF entry remains bounded and never runs input-dependent fallback.
- Counts and byte sizes use checked arithmetic before allocation or transition.
- Test hooks are compile-time gated, bounded, redacted, and absent from release symbols.
- Phase 1 snapshots say `:preproduction_threaded`; only Phase 5 may claim `:bounded_native_pool`.

## Exit Criteria

- Worker and queue capacity are finite, validated, and observable.
- Saturation immediately returns `:busy` without scheduler blocking.
- Every job owns its post-submit state and has one terminal cleanup owner.
- Caller death, timeout, halt, close, and shutdown cancel safely.
- Stateful document and cursor operations cannot conflict.
- Telemetry explains latency and capacity without user content.
- Partial startup and shutdown leak no jobs, resources, environments, or threads.
- All Milestone 1–3 gates remain green and the native-pool spec is active.
