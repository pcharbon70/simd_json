---
id: simd_json.owned_native_jobs_and_bounded_fifo
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

# Owned Native Jobs and Bounded FIFO

## Context

Fixed native workers exist, but Phase 2 intentionally gave them no work.
Before public operations can move off the qualified Zigler-threaded bridge, the
pool needs a bounded ownership and admission primitive whose saturation and
shutdown behavior can be tested independently of document and cursor resources.

## Decision

The native pool owns one condition-backed intrusive FIFO. Each admitted job
copies its validated fixture bytes into allocator-owned memory and records a
bounded operation kind, monotonic request identity, enqueue time, cancellation
flag, and terminal state. One destruction path releases the copied bytes and
descriptor exactly once.

Submission checks queued capacity while holding the queue mutex and returns
busy before allocating when the configured queue is full. Fixed workers alone
dequeue jobs. Shutdown stops admission, wakes workers, drains accepted work,
joins every worker, and releases all retained bytes.

Phase 3 exposes submission, pause, counters, and FIFO evidence only through
test-only NIFs. Public open, select, and stream operations remain on their
qualified Zigler-threaded routes, and the executor marker remains
`:preproduction_threaded`.

## Consequences

Capacity, FIFO order, immediate rejection, ownership, and shutdown cleanup can
be qualified deterministically before resource retention, result delivery, and
cancellation races are introduced. The fixture path is not a production
executor and cannot be used as evidence that public routing has switched.
