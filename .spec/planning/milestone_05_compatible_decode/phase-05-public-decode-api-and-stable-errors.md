# Phase 5 — Public Decode API, Raising Wrapper, and Stable Errors

Back to plan: [README](./README.md)

- [ ] 5 Phase - Publish the safe eager decode compatibility surface while
  preserving bounded native execution and redacted failures.

## 5.1 Section — Tagged and Raising Public API

- [x] 5.1 Section - Expose binary-only `decode/1,2` and Elixir-only
  `decode!/1,2` wrappers over the existing typed pool operation.
  - [x] 5.1.1 Task - Apply the closed empty-option preflight before admission.
  - [x] 5.1.2 Task - Make both public forms share one native execution path.

## 5.2 Section — Stable Shared Errors

- [x] 5.2 Section - Translate parse, capacity, cancellation, number, and limit
  failures into one redacted `SimdJson.Error` representation.
  - [x] 5.2.1 Task - Preserve safe offsets and native codes where available.
  - [x] 5.2.2 Task - Raise the exact tagged error value from bang wrappers.

## 5.3 Section — Documentation and Public Surface

- [x] 5.3 Section - Document compatibility, eager-allocation tradeoffs,
  unsupported options, and the locked public surface.
  - [x] 5.3.1 Task - Add doctests for every public arity and top-level value.
  - [x] 5.3.2 Task - Keep native fixtures and pool controls private.

## 5.4 Section — Phase 5 Integration and Qualification

- [ ] 5.4 Section - Reconcile API, runtime, package, specs, regressions, and
  qualification state for the public decode release.
  - [ ] 5.4.1 Task - Cover success, malformed input, options, bang parity,
    saturation, telemetry, and cleanup through the public API.
  - [ ] 5.4.2 Task - Reconcile formatting, release symbols, traceability,
    fingerprint, and SpecLed state.
