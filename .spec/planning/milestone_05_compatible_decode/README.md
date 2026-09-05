# Milestone 5 Compatible Decode Implementation Plan

<!-- covers: simd_json.package.documentation_layout -->

This plan adds eager JSON materialization without bypassing the bounded native
pool, creating atoms from input, or weakening the ownership and cancellation
contracts established by Milestones 1–4.

## Source Authority

1. [Milestone 5 — Jason-Compatible Decode API](../../../docs/milestones/05-compatible-decode-api.md)
2. [Safe Decode Compatibility Contract](../../decisions/0016-safe-decode-compatibility-contract.md)
3. [Compatible Decode API](../../specs/decode_api.spec.md)
4. Active Milestone 1–4 decisions and specifications.

## Phase Order

1. [Phase 1 — Compatibility Contract and Preflight](./phase-01-compatibility-contract-and-preflight.md)
2. [Phase 2 — ABI v4 and Iterative Materializer Ownership](./phase-02-abi-v4-and-iterative-materializer-ownership.md)
3. [Phase 3 — Scalar, Container, Number, and String Materialization](./phase-03-value-materialization.md)
4. [Phase 4 — Bounded Pool Execution, Cancellation, and Limits](./phase-04-bounded-execution-and-limits.md)
5. [Phase 5 — Public Decode API, Raising Wrapper, and Stable Errors](./phase-05-public-decode-api-and-stable-errors.md)
6. [Phase 6 — Differential Qualification, Benchmarks, and Activation](./phase-06-differential-qualification-benchmarks-and-activation.md)

## Contract Ownership by Phase

| Phase | Primary responsibility |
| --- | --- |
| 1 | Binary-only input, closed empty option grammar, Jason reference matrix, planned contract, and native-free preflight. |
| 2 | ABI v4 descriptors, explicit materializer stack, private result ownership, and rollback. |
| 3 | Complete JSON value mapping, copied keys/strings, exact numbers, duplicate keys, Unicode, and depth behavior. |
| 4 | Typed pool jobs, cancellation checkpoints, resource limits, telemetry, and lifecycle cleanup. |
| 5 | `decode/1,2`, `decode!/1,2`, shared errors, docs, and locked public surface. |
| 6 | Differential corpus, end-to-end performance/memory evidence, sanitizer qualification, and activation. |

## Shared Conventions

- Checkboxes close only with implementation and executable evidence.
- Input never creates atoms; object keys are binaries.
- Eager decode never bypasses Milestone 4 admission or cancellation.
- Compatibility means the published pinned matrix, not every Jason option.
- Native traversal uses an explicit bounded stack rather than recursion.

## Exit Criteria

- Every JSON value type materializes through the bounded pool.
- Exact values and accepted/rejected inputs match the published matrix.
- Keys and strings are independent binaries and numbers never silently round.
- Limits, cancellation, and failures release partial state exactly once.
- Differential, scheduler, memory, benchmark, and sanitizer gates pass.
