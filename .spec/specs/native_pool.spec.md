# Native Worker Pool and Admission

Milestone 5 Phase 1 hardens the existing early-stream-halt qualification to
await asynchronous pool cleanup before asserting quiescence; runtime behavior
and capacity are unchanged.

Current-truth contract for Milestone 4 fixed-capacity native execution,
bounded admission, cancellation, lifecycle, and operational evidence.

## Intent

This subject replaces the provisional Zigler-threaded bridge with a
library-owned execution subsystem. Milestone 4 Phase 5 routes public open,
cleanup, select, stream setup, and next-batch work through fixed native workers
with bounded admission. Elixir emits redacted operational telemetry from
native timing metadata, while shutdown drains and joins the pool. Phase 6
qualifies saturation, races, sanitizers, and operational evidence.

```spec-meta
id: simd_json.native_pool
kind: subsystem
status: active
summary: Native jobs run through fixed workers and a bounded non-blocking queue with explicit cancellation and redacted telemetry.
surface:
  - lib/simd_json/native/**
  - native/**
  - test/**/*pool*
  - test/**/*admission*
  - docs/milestones/04-worker-pool-and-operations.md
decisions:
  - simd_json.bounded_native_pool_configuration_and_admission
  - simd_json.fixed_native_worker_lifecycle
  - simd_json.owned_native_jobs_and_bounded_fifo
  - simd_json.monitored_delivery_and_resource_serialization
  - simd_json.production_native_pool_routing_and_telemetry
  - simd_json.native_pool_qualification_and_activation
```

## Requirements

```spec-requirements
- id: simd_json.native_pool.fixed_configuration
  statement: The application shall normalize native_workers and native_queue_size once at startup using documented finite defaults and the exact accepted bounds of 1..64 workers and 1..4096 queued jobs.
  priority: must
  stability: stable

- id: simd_json.native_pool.startup_validation
  statement: Invalid pool configuration shall fail before operation admission with a controlled argument error and shall never clamp, ignore, or select an unbounded or dirty-scheduler fallback.
  priority: must
  stability: stable

- id: simd_json.native_pool.redacted_snapshot
  statement: Internal diagnostics shall expose only bounded effective capacity, explicit-source flags, and the honest executor phase without application terms, caller identity, request references, paths, JSON content, or native addresses.
  priority: must
  stability: stable

- id: simd_json.native_pool.nonblocking_bounded_admission
  statement: The production submit boundary shall admit at most the configured running and queued capacity and shall immediately return busy on saturation without waiting, spinning, allocating an unowned job, or executing input-dependent fallback work.
  priority: must
  stability: stable

- id: simd_json.native_pool.owned_jobs
  statement: Every admitted job shall own its validated arguments, retained resources, caller monitor, request correlation, cancellation flag, timing metadata, and exactly one terminal cleanup path.
  priority: must
  stability: stable

- id: simd_json.native_pool.fixed_workers
  statement: The native subsystem shall create no more than the configured fixed worker count and shall reuse those workers for open, select, stream setup, and next-batch jobs without an OS thread per request.
  priority: must
  stability: stable

- id: simd_json.native_pool.cancellation
  statement: Caller death, timeout, early halt, close, and shutdown shall cancel queued work before execution and running work at bounded safe checkpoints without duplicate delivery or cleanup.
  priority: must
  stability: evolving

- id: simd_json.native_pool.resource_serialization
  statement: Independent resources may run concurrently while one document or cursor admits at most one conflicting state-advancing job and close prevents later admission.
  priority: must
  stability: stable

- id: simd_json.native_pool.telemetry
  statement: Elixir shall emit bounded telemetry for queue, execution, conversion, sizes, capacity, operation, outcome, rejection, and cancellation without user content or high-cardinality identities.
  priority: must
  stability: evolving

- id: simd_json.native_pool.shutdown
  statement: Startup failure, application stop, NIF unload, and supported upgrade boundaries shall stop admission, cancel or drain jobs, join every worker, and release shared state exactly once.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.native_pool.configuration_preflight
  covers:
    - simd_json.native_pool.fixed_configuration
    - simd_json.native_pool.startup_validation
    - simd_json.native_pool.redacted_snapshot
  given:
    - Default, boundary, invalid, and explicitly configured pool values
  when:
    - Configuration is normalized before coordinator startup
  then:
    - Only exact integer domains are accepted
    - Equivalent valid inputs produce identical effective capacity
    - Diagnostics identify the executor honestly and reveal no caller data

- id: simd_json.native_pool.saturation
  covers:
    - simd_json.native_pool.nonblocking_bounded_admission
    - simd_json.native_pool.owned_jobs
    - simd_json.native_pool.fixed_workers
  given:
    - More independent valid operations than all worker and queue slots
  when:
    - Callers submit concurrently
  then:
    - Running and queued counts never exceed configuration
    - Excess calls immediately receive a redacted busy error
    - Accepted work produces one correlated terminal result and cleanup

- id: simd_json.native_pool.cancel_close_shutdown_races
  covers:
    - simd_json.native_pool.cancellation
    - simd_json.native_pool.resource_serialization
    - simd_json.native_pool.shutdown
  given:
    - Queued and running jobs racing caller death, timeout, close, and shutdown
  when:
    - Cancellation and completion compete
  then:
    - One terminal owner wins without double-send or double-free
    - Conflicting resource work never overlaps
    - Workers join and every retained gauge returns to baseline

- id: simd_json.native_pool.operational_visibility
  covers:
    - simd_json.native_pool.telemetry
  given:
    - Successful, failed, rejected, and cancelled jobs across operation kinds
  when:
    - Operational handlers observe the execution subsystem
  then:
    - Measurements explain capacity and latency with bounded metadata
    - JSON, caller paths, selected values, PIDs, and request references are absent
```

## Verification

```spec-verification
- kind: command
  target: MIX_ENV=test mix test test/native/pool_options_test.exs
  execute: true
  covers:
    - simd_json.native_pool.fixed_configuration
    - simd_json.native_pool.startup_validation
    - simd_json.native_pool.redacted_snapshot
    - simd_json.native_pool.configuration_preflight

- kind: command
  target: MIX_ENV=test mix test test/native/pool_worker_lifecycle_test.exs
  execute: true
  covers:
    - simd_json.native_pool.fixed_workers
    - simd_json.native_pool.shutdown

- kind: command
  target: MIX_ENV=test mix test test/native/pool_queue_test.exs
  execute: true
  covers:
    - simd_json.native_pool.nonblocking_bounded_admission
    - simd_json.native_pool.owned_jobs
    - simd_json.native_pool.fixed_workers
    - simd_json.native_pool.shutdown
    - simd_json.native_pool.saturation

- kind: command
  target: MIX_ENV=test mix test test/native/pool_cancellation_test.exs test/native/pool_delivery_test.exs test/native/pool_resource_serialization_test.exs
  execute: true
  covers:
    - simd_json.native_pool.cancellation
    - simd_json.native_pool.owned_jobs
    - simd_json.native_pool.resource_serialization
    - simd_json.native_pool.shutdown
    - simd_json.native_pool.cancel_close_shutdown_races

- kind: command
  target: bash scripts/ci/qualify_native_pool.sh
  execute: true
  covers:
    - simd_json.native_pool.nonblocking_bounded_admission
    - simd_json.native_pool.owned_jobs
    - simd_json.native_pool.fixed_workers
    - simd_json.native_pool.cancellation
    - simd_json.native_pool.resource_serialization
    - simd_json.native_pool.telemetry
    - simd_json.native_pool.shutdown
    - simd_json.native_pool.saturation
    - simd_json.native_pool.cancel_close_shutdown_races
    - simd_json.native_pool.operational_visibility
```
