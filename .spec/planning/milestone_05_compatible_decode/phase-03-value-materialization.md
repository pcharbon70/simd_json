# Phase 3 — Scalar, Container, Number, and String Materialization

Back to plan: [README](./README.md)

- [ ] 3 Phase - Populate the ABI v4 result graph with every JSON value while
  preserving exact values, source order, copied bytes, and bounded depth.

## 3.1 Section — Iterative Container Graph

- [x] 3.1 Section - Traverse objects and arrays with explicit native frames and
  publish checked contiguous edge ranges in source order.
  - [x] 3.1.1 Task - Materialize empty, nested, and mixed containers without
    native recursion.
  - [x] 3.1.2 Task - Enforce maximum depth and container-entry limits during
    traversal with transactional rollback.

## 3.2 Section — Strings, Keys, Booleans, and Null

- [ ] 3.2 Section - Copy decoded strings and object keys into result-owned byte
  storage and materialize existing boolean/null values.
  - [ ] 3.2.1 Task - Cover escapes, Unicode, embedded nulls, empty values, and
    malformed UTF-8/surrogates.
  - [ ] 3.2.2 Task - Preserve duplicate object edges in source order so the
    BEAM conversion can deterministically apply last-key-wins semantics.

## 3.3 Section — Exact Numeric Materialization

- [ ] 3.3 Section - Distinguish signed, unsigned, floating, and unsupported
  integer tokens without silent rounding.
  - [ ] 3.3.1 Task - Preserve native 64-bit integers and finite IEEE-754 values.
  - [ ] 3.3.2 Task - Reject big integers and non-finite float results with the
    stable number-out-of-range status until arbitrary precision conversion.

## 3.4 Section — Phase 3 Integration and Qualification

- [ ] 3.4 Section - Validate complete graphs in Zig and reconcile native builds,
  package inputs, sanitizer coverage, specs, and qualification evidence.
  - [ ] 3.4.1 Task - Prove graph range/index invariants and all value tags in C
    and Zig ordinary/sanitizer matrices.
  - [ ] 3.4.2 Task - Reconcile manifest, fingerprint, formatting, regressions,
    traceability, and SpecLed state.
