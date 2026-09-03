# `.spec/decisions`

Use this folder for durable cross-cutting decisions that shape the current Spec Led Development workspace.

<!-- covers: spec.workspace.decisions_readme_present -->

## What Belongs Here

- ADRs that affect multiple authored subjects
- verification policy that should stay consistent over time
- package-wide or workspace-wide operating rules that are more stable than a pull request discussion

## What Does Not Belong Here

- in-flight proposal notes
- branch-local implementation plans
- one-off rationale that only matters inside a single subject file

## Workflow

1. Update the current-truth subject specs in `.spec/specs/`.
2. Add or revise an ADR here only when the change is cross-cutting and should stay durable.
3. Use Git history and pull requests as the time dimension for how the change evolved.

## Accepted Decisions

### Milestone 1 — Native Foundation

- [Native Stack and C ABI Boundary](./0001-native-stack-and-c-abi.md)
- [Document Resource and Input Buffer Ownership](./0002-document-resource-and-buffer-ownership.md)
- [Off-Scheduler Native Execution](./0003-off-scheduler-native-execution.md)

### Milestone 2 — Projection API

- [Projection API and Validation Contract](./0004-projection-api-and-validation-contract.md)
- [Prefix-Sharing Native Projection Engine](./0005-prefix-sharing-native-projection-engine.md)
- [Projection Admission, Consumption, and Lifetime](./0006-projection-admission-consumption-and-lifetime.md)

### Milestone 3 — Batched Array Streaming

- [Lazy Stream API and Bounded Options](./0007-lazy-stream-api-and-bounded-options.md)
- [Forward-Only Batched Array Cursor](./0008-forward-only-batched-array-cursor.md)
- [Stream Ownership, Backpressure, and Lifetime](./0009-stream-ownership-backpressure-and-lifetime.md)

### Milestone 4 — Production Native Concurrency

- [Bounded Native Pool Configuration and Admission](./0010-bounded-native-pool-configuration-and-admission.md)
