# Phase 6 — Saturation Qualification and Activation

Back to plan: [README](./README.md)

- [ ] 6 Phase - Qualify the production pool under saturation and activate the
  Milestone 4 contract.

## 6.1 Section — Saturation and FIFO Fairness

- [x] 6.1 Section - Prove exact capacity, immediate rejection, fixed workers,
  and FIFO progress under sustained excess demand.
  - [x] 6.1.1 Task - Saturate every running and queued slot repeatedly.
  - [x] 6.1.2 Task - Prove accepted jobs complete in admission order without
    starvation and rejected jobs retain no bytes.

## 6.2 Section — Latency and Memory Qualification

- [ ] 6.2 Section - Record bounded admission, scheduler wake-up, queue,
  execution, cancellation, and retained-memory evidence.
  - [ ] 6.2.1 Task - Add a deterministic operational qualification profile.
  - [ ] 6.2.2 Task - Retain machine-readable percentile and capacity evidence.

## 6.3 Section — Race, Shutdown, and Sanitizer Matrix

- [ ] 6.3 Section - Exercise cancellation, delivery, close, and shutdown races
  through ordinary and sanitizer-backed qualification.
  - [ ] 6.3.1 Task - Repeat race scenarios with fixed seeds and full cleanup.
  - [ ] 6.3.2 Task - Aggregate native, release-symbol, and regression gates in
    one pool qualification command.

## 6.4 Section — Operations Documentation and Spec Activation

- [ ] 6.4 Section - Publish pool sizing and operational limits, activate the
  native-pool contract, and reconcile all current truth.
  - [ ] 6.4.1 Task - Document sizing, saturation, telemetry, cancellation,
    shutdown, upgrade, and troubleshooting guidance.
  - [ ] 6.4.2 Task - Run formatting, package, native, regression, traceability,
    and spec-led gates with no unchecked Milestone 4 work.
