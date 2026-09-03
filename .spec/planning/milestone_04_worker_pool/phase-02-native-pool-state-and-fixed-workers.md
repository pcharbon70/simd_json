# Phase 2 — Native Pool State and Fixed Workers

Back to plan: [README](./README.md)

- [ ] 2 Phase - Establish the native pool lifetime and fixed idle workers
  without routing production jobs or claiming bounded-pool execution.

## 2.1 Section — Shared Pool State

- [x] 2.1 Section - Define one native runtime owning bounded configuration,
  synchronization primitives, thread handles, and lifecycle state.
  - [x] 2.1.1 Task - Allocate exactly one mutex, condition, and bounded handle array.
  - [x] 2.1.2 Task - Keep queue storage and production admission absent until Phase 3.

## 2.2 Section — Fixed Worker Startup

- [x] 2.2 Section - Start exactly the normalized worker count once and keep
  workers asleep on the native condition without polling or per-request threads.
  - [x] 2.2.1 Task - Wire normalized startup through the coordinator boundary.
  - [x] 2.2.2 Task - Make identical startup idempotent and reject conflicting starts.

## 2.3 Section — Rollback and Join Primitives

- [ ] 2.3 Section - Stop admission, wake workers, join every started thread, and
  release primitives in reverse order, including partial-start failure.
  - [ ] 2.3.1 Task - Add bounded test-only thread-creation fault injection.
  - [ ] 2.3.2 Task - Prove partial startup leaves no live worker or allocation.

## 2.4 Section — Phase 2 Integration Tests

- [ ] 2.4 Section - Verify exact worker counts, sleeping behavior, idempotence,
  rollback, repeated start/stop, redaction, symbols, and prior milestone gates.
  - [ ] 2.4.1 Task - Add native and BEAM lifecycle coverage.
  - [ ] 2.4.2 Task - Run formatting, regression, sanitizer, and spec checks.
