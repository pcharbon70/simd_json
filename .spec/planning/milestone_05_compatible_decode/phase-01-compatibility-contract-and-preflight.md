# Phase 1 — Compatibility Contract and Preflight

Back to plan: [README](./README.md)

- [x] 1 Phase - Freeze the safe Jason-compatible decode boundary and implement
  its native-free preflight without publishing decode functions.

## 1.1 Section — Compatibility Contract and Phase Plan

- [x] 1.1 Section - Define the supported input, option, value, duplicate-key,
  number, Unicode, error, and safety contract before native implementation.
  - [x] 1.1.1 Task - Accept the safe compatibility ADR and planned decode spec.
  - [x] 1.1.2 Task - Publish the ordered six-phase implementation plan and
    explicit Jason 1.4.5 compatibility matrix.

## 1.2 Section — Native-free Decode Preflight

- [x] 1.2 Section - Normalize binary input and the closed option grammar before
  any request, native allocation, parsing, or document transition.
  - [x] 1.2.1 Task - Accept only a binary plus an empty proper keyword list.
  - [x] 1.2.2 Task - Retain a bounded opaque snapshot with no source content.

## 1.3 Section — Decode Error and Limit Vocabulary

- [x] 1.3 Section - Reserve stable materialization and configured-limit errors
  while preserving redacted inspection.
  - [x] 1.3.1 Task - Add depth, output-size, and container-size limit reasons.
  - [x] 1.3.2 Task - Prove forged metadata and input never escape inspection.

## 1.4 Section — Phase 1 Integration and Package Boundaries

- [x] 1.4 Section - Lock the unpublished decode surface, package the authored
  contract, and run SpecLed plus regression gates.
  - [x] 1.4.1 Task - Prove preflight performs no native admission and decode
    functions remain absent.
  - [x] 1.4.2 Task - Reconcile package, manifest, qualification fingerprint,
    formatting, tests, traceability, and spec state.
