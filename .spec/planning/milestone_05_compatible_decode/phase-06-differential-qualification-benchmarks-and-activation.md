# Phase 6 — Differential Qualification, Benchmarks, and Activation

Back to plan: [README](./README.md)

- [x] 6 Phase - Qualify the safe decode compatibility contract and activate
  Milestone 5 on the supported target.

## 6.1 Section — Differential Compatibility Corpus

- [x] 6.1 Section - Compare public decode behavior with pinned Jason 1.4.5
  across valid values, rejected inputs, numbers, Unicode, and duplicate keys.
  - [x] 6.1.1 Task - Record deterministic valid and invalid corpus parity.
  - [x] 6.1.2 Task - Exercise generated nested combinations and exact values.

## 6.2 Section — Performance, Memory, and Scheduler Evidence

- [x] 6.2 Section - Record end-to-end decode latency, throughput, reductions,
  memory, garbage collection, and scheduler responsiveness against Jason.
  - [x] 6.2.1 Task - Add deterministic small, medium, array, nested, string,
    number, success, and malformed benchmark profiles.
  - [x] 6.2.2 Task - Retain machine-readable measurements and cleanup gauges.

## 6.3 Section — Sanitizer and Qualification Aggregation

- [x] 6.3 Section - Aggregate compatibility, runtime, benchmark, native,
  sanitizer, symbol, package, and regression gates in one command.
  - [x] 6.3.1 Task - Run cancellation and failure cleanup with fixed seeds.
  - [x] 6.3.2 Task - Bind the evidence bundle to revision, tree, environment,
    fingerprint, and checksums.

## 6.4 Section — Acceptance and Spec Activation

- [x] 6.4 Section - Publish accepted compatibility and operational guidance,
  activate the decode subject, and reconcile all current truth.
  - [x] 6.4.1 Task - Document supported behavior, known differences, sizing,
    saturation, telemetry, and eager-allocation tradeoffs.
  - [x] 6.4.2 Task - Close every Milestone 5 checkbox and pass formatting,
    docs, release, traceability, qualification, and SpecLed gates.
