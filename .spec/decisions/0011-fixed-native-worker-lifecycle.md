---
id: simd_json.fixed_native_worker_lifecycle
status: accepted
date: 2026-09-03
affects:
  - simd_json.native_pool
  - simd_json.native_execution
  - simd_json.document_api
  - simd_json.document_resource
  - simd_json.projection_api
  - simd_json.projection_execution
  - simd_json.stream_execution
  - simd_json.package
---

# Fixed Native Worker Lifecycle

## Context

Phase 1 established bounded configuration but intentionally created no native
pool state. Phase 2 must establish deterministic worker ownership without
prematurely changing request routing.

## Decision

Application startup passes the normalized pool configuration across the
coordinator boundary once. Native state owns one bounded handle array, one
mutex, one condition, and exactly the configured sleeping worker threads.
Identical startup is idempotent and conflicting startup fails.

Partial creation stops and joins every created worker before releasing shared
state. Shutdown stops acceptance, wakes and joins every worker, then releases
the condition, mutex, handles, and runtime. Phase 2 workers accept no jobs and
do not replace or modify the qualified threaded execution and resource paths.

## Consequences

The process has fixed native capacity and deterministic rollback/join
primitives before jobs exist. Production admission, cancellation, delivery,
and the `:bounded_native_pool` executor marker remain deferred.
