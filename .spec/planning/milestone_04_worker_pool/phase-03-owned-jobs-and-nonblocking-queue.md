# Phase 3 — Owned Jobs and Non-blocking Queue

Back to plan: [README](./README.md)

- [ ] 3 Phase - Establish owned native jobs and exact bounded FIFO admission
  without routing public operations or enabling production pool diagnostics.

## 3.1 Section — Owned Job Descriptor

- [x] 3.1 Section - Define a native descriptor that owns copied arguments,
  correlation, operation kind, cancellation state, timing, and one cleanup path.
  - [x] 3.1.1 Task - Copy post-submit bytes into allocator-owned memory.
  - [x] 3.1.2 Task - Bound operation kind, request identity, and terminal state.

## 3.2 Section — FIFO Worker Queue

- [x] 3.2 Section - Add one condition-backed FIFO consumed only by fixed workers.
  - [x] 3.2.1 Task - Preserve enqueue order and wake workers without polling.
  - [x] 3.2.2 Task - Drain or destroy every queued descriptor during shutdown.

## 3.3 Section — Exact Non-blocking Admission

- [ ] 3.3 Section - Reject immediately at queue capacity before allocating a job.
  - [ ] 3.3.1 Task - Account queued, running, completed, rejected, and retained bytes.
  - [ ] 3.3.2 Task - Add bounded test-only pause controls for deterministic saturation.

## 3.4 Section — Phase 3 Integration Tests

- [ ] 3.4 Section - Prove ownership, FIFO, exact capacity, immediate busy,
  shutdown cleanup, redaction, unchanged routing, and earlier milestone gates.
  - [ ] 3.4.1 Task - Add focused concurrency and lifecycle coverage.
  - [ ] 3.4.2 Task - Run regression, formatting, native, and spec qualification.
