# Phase 4 — Cancellation, Delivery, and Resource Serialization

Back to plan: [README](./README.md)

- [ ] 4 Phase - Establish monitored cancellation, unique result delivery, and
  per-resource serialization without routing public operations or enabling
  production pool diagnostics.

## 4.1 Section — Caller Monitoring and Cooperative Cancellation

- [x] 4.1 Section - Bind each cancellable fixture job to a native request
  resource and caller monitor with one terminal cleanup owner.
  - [x] 4.1.1 Task - Cancel queued and running jobs from explicit requests,
    caller death, and shutdown checkpoints.
  - [x] 4.1.2 Task - Remove monitors and release request state safely when
    cancellation races completion.

## 4.2 Section — Correlated Result Delivery

- [ ] 4.2 Section - Deliver at most one result to the matching live caller by
  unique reference using an independently allocated NIF environment.
  - [ ] 4.2.1 Task - Discard failed or orphaned sends as normal cleanup.
  - [ ] 4.2.2 Task - Account delivered, discarded, and cancelled terminals.

## 4.3 Section — Resource Serialization and Close Interlocks

- [ ] 4.3 Section - Serialize conflicting state-advancing fixture jobs while
  allowing independent resources to execute concurrently.
  - [ ] 4.3.1 Task - Reject overlapping work and prevent admission after close.
  - [ ] 4.3.2 Task - Release reservations exactly once across cancellation,
    completion, and close races.

## 4.4 Section — Phase 4 Integration Tests

- [ ] 4.4 Section - Prove caller death, timeout-style cancellation, unique
  delivery, orphan discard, resource races, shutdown cleanup, unchanged
  routing, and earlier milestone gates.
  - [ ] 4.4.1 Task - Add focused race and lifecycle coverage.
  - [ ] 4.4.2 Task - Run regression, formatting, native, and spec qualification.
