# Phase 5 — Telemetry, Public Operations, and Lifecycle

Back to plan: [README](./README.md)

- [x] 5 Phase - Route the public operation families through the bounded native
  pool, emit redacted operational telemetry, and own the pool lifecycle.

## 5.1 Section — Public Open and Select Routing

- [x] 5.1 Section - Execute public document open, cleanup, and projection jobs
  on the configured fixed native workers.
  - [x] 5.1.1 Task - Retain operation and document resources in owned pool jobs.
  - [x] 5.1.2 Task - Return correlated results and immediate busy failures to
    the existing stable public wrappers.

## 5.2 Section — Public Stream Routing

- [x] 5.2 Section - Execute lazy stream setup and each demand-driven batch on
  the same bounded native pool.
  - [x] 5.2.1 Task - Retain copied projection and target terms for setup jobs.
  - [x] 5.2.2 Task - Retain cursor resources and preserve one-in-flight demand.

## 5.3 Section — Redacted Telemetry and Lifecycle

- [x] 5.3 Section - Emit bounded queue and job telemetry and make application,
  unload, and upgrade shutdown ownership explicit.
  - [x] 5.3.1 Task - Publish duration, size, capacity, operation, and outcome
    data without caller identity, references, paths, or JSON content.
  - [x] 5.3.2 Task - Stop admission, cancel or drain work, join fixed workers,
    and reject unsafe in-place native upgrades.

## 5.4 Section — Phase 5 Integration and Contract Reconciliation

- [x] 5.4 Section - Prove production routing, telemetry redaction, lifecycle,
  release surface, and all earlier milestone regressions.
  - [x] 5.4.1 Task - Add focused public-operation, telemetry, and shutdown tests.
  - [x] 5.4.2 Task - Reconcile current truth and run formatting, native, package,
    regression, and spec-led gates.
