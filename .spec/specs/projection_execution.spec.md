# Projection Execution and Lifecycle

Milestone 5 Phase 4 shares fixed-worker dispatch and cancellation accounting
with decode while leaving projection reservations and conversion unchanged.

Projection admission, cancellation, conversion, and lifecycle behavior remain
regression-locked under cumulative ABI v4.

Milestone 5 Phase 1 introduces no projection job or lifecycle change; decode
preflight remains native-free and independent of projection resources.

Milestone 4 Phase 5 retains the normalized plan, binary or document source,
ownership state, cancellation state, and result environment in one typed pool
job executed by a fixed native worker.

Milestone 4 Phase 4 proved monitored fixture jobs; Phase 5 applies those
ownership and delivery rules to production projection jobs.

Milestone 3 Phase 6 reruns this active subject as an inherited regression gate.
Streaming continues to reuse the same normalized projection engine and
threaded coordinator without weakening Milestone 2 ownership, scheduler,
lifecycle, or sparse-allocation evidence.

Active current-truth contract for Milestone 2 threaded projection admission,
one-shot document consumption, temporary binary-source ownership,
cancellation, cleanup, and end-to-end qualification.

## Intent

This subject makes projection scheduler-safe and lifetime-safe. It ensures the
binary and document forms share one correlated native operation model, a
forward-only document has deterministic post-attempt state, and no result or
worker can outlive the resources it dereferences.

Phase 1 now establishes and executes the pre-admission half of that boundary.
The complete projection is validated in reduction-yielding Elixir code before
source inspection or request creation; test-only admission accounting plus a
genuine fresh document prove invalid terms do not enter Zigler, allocate native
operation state, advance the generation, or alter document lifecycle. No
projection worker, reservation, selecting/consumed state, or binary temporary
document exists yet, so the subject remains planned under its complete
bootstrap exception.
Phase 2 freezes the C execution signature and adds an idempotent Zig plan owner.
Phase 3 now exercises that single execution call in standalone C/Zig harnesses,
claims the native cursor once, supports a hidden operation-owned cancellation
probe, and frees temporary slot storage on success and every failure. It still
adds no projection operation kind, owner-first reservation, threaded admission,
BEAM term conversion, temporary binary document, callback cleanup, or delivery;
those Phase 4 lifecycle requirements remain planned under the complete
bootstrap exception.
Phase 4 now implements that private vertical slice. One correlated threaded
projection retains either a binary or genuine document, compiles one plan,
executes one guided traversal, constructs one complete private-environment map,
and explicitly copies it through the generated join. Documents implement
owner-first `fresh -> selecting -> consumed`, proven pre-worker rollback, a
cursor-commit point, close interlock, and generation checks. Binary operations
own unpublished padded input/parser/document graphs. Integration tests force
out-of-order completion, every binary/document cancellation boundary,
conversion allocation failure, close and application shutdown, GC handoff
retry, copied-result independence, a preliminary 4 MiB heartbeat profile, and
all live gauges back to baseline. The subject stays planned only because the
formal sanitizer/scheduler/Jason qualification in Phase 6 has not activated the
complete Milestone 2 contract. Phase 5 now routes the public `select/2` binary
and genuine-document forms through that same correlated operation, performs
complete projection preflight and bounded genuine-resource/owner/lifecycle
checks before reservation, and preserves retry after invalid input or proven
submission rejection. Public one-shot, copied-result, ownership, close,
redaction, and baseline tests exercise the boundary without adding options,
plans, diagnostics, or a second execution path. Phase 6 now records the formal
projection heartbeat, seeded lifetime recovery, frozen Jason comparison, and
supported-target acceptance evidence, so the subject is active.
Milestone 3 Phase 1 invokes only the active BEAM projection validator while
normalizing future per-row fields. Valid and invalid stream construction create
no projection admission, reservation, operation, plan, worker entry, slot, or
temporary document graph, so active `select/2` execution and qualification
remain unchanged.
Milestone 3 Phase 2 gives the private cursor one operation-owned projection
plan but performs no row execution and admits no threaded stream request. The
active `select/2` reservation, worker, cancellation, conversion, and cleanup
paths are regression-tested unchanged under ABI v3.
Milestone 3 Phase 4 reuses the projection plan and scalar conversion inside a
private threaded cursor fixture. The shared document use state now excludes a
stream reservation from selection, while the active public `select/2` worker,
result shape, error translation, and qualification boundary remain unchanged.

Milestone 3 Phase 5 accepts the normalized field plan and target at lazy setup, compiles one cursor-owned native plan, and uses output-slot order to atomically convert each native batch into exact-key BEAM maps.

Milestone 4 Phase 1 freezes finite worker and queue configuration but creates
no pool job or global admission boundary. Projection correlation, retention,
cancellation, document consumption, and cleanup continue through the existing
qualified pre-production coordinator unchanged.

```spec-meta
id: simd_json.projection_execution
kind: subsystem
status: active
verification_minimum_strength: executed
summary: Milestone 2 runs one-shot projection off scheduler with owner-first admission, retained resources, deterministic consumption, and qualified cleanup.
surface:
  - native/**
  - lib/simd_json/**/*.ex
  - test/**/*projection*
  - test/**/*scheduler*
  - test/qualification/**
  - bench/**/*projection*
  - docs/milestones/02-projection-api.md
decisions:
  - simd_json.document_resource_and_buffer_ownership
  - simd_json.off_scheduler_native_execution
  - simd_json.projection_admission_consumption_and_lifetime
  - simd_json.owned_native_jobs_and_bounded_fifo
  - simd_json.monitored_delivery_and_resource_serialization
```

## Requirements

```spec-requirements
- id: simd_json.projection_execution.threaded_projection
  statement: Projection compilation, input-dependent traversal, result conversion, and potentially large cleanup shall execute through the correlated Zigler-threaded path rather than an ordinary or dirty CPU NIF.
  priority: must
  stability: evolving

- id: simd_json.projection_execution.one_correlated_operation
  statement: Each public select/2 call shall create one uniquely correlated native operation with one terminal result, and late, duplicate, stale, mismatched, cancelled, or orphaned projection results shall be discarded only after cleanup.
  priority: must
  stability: stable

- id: simd_json.projection_execution.owner_first_admission
  statement: Document projection shall validate the genuine resource and caller ownership before revealing lifecycle, generation, selecting, or consumed state and before reserving native work.
  priority: must
  stability: stable

- id: simd_json.projection_execution.exclusive_document_selection
  statement: A fresh document shall admit at most one projection by moving atomically from fresh to selecting, and no second projection shall access its cursor concurrently.
  priority: must
  stability: stable

- id: simd_json.projection_execution.committed_consumption
  statement: After a worker crosses its first cursor-access boundary, document projection shall end in consumed on success, parse or path failure, conversion failure, cancellation, caller death, or internal failure and shall never rewind or silently reparse.
  priority: must
  stability: stable

- id: simd_json.projection_execution.preadmission_nonconsumption
  statement: Invalid arguments, projection validation failures, non-owner and lifecycle rejection, and proven pre-worker submission rejection shall leave a fresh document unconsumed and eligible for a later valid owner projection.
  priority: must
  stability: stable

- id: simd_json.projection_execution.generation_and_resource_retention
  statement: Every projection operation shall retain its document, input, plan, result environment, and operation state and validate the captured generation before native dereference and delivery until terminal cleanup completes.
  priority: must
  stability: stable

- id: simd_json.projection_execution.binary_temporary_document
  statement: Binary-source select shall create, traverse, and destroy an unpublished temporary padded input, parser, document, plan, and slot graph within one threaded operation before returning success or failure.
  priority: must
  stability: stable

- id: simd_json.projection_execution.close_interlock
  statement: Close, garbage collection, application shutdown, and NIF unload shall prevent new projection admission, cancel active selection at safe boundaries, suppress stale delivery, and join exactly-once dependency-safe cleanup without blocking a normal scheduler.
  priority: must
  stability: stable

- id: simd_json.projection_execution.cancellation_boundaries
  statement: Projection shall check cancellation before plan compilation, before cursor access, between bounded traversal units, before and during bounded term conversion, and before delivery while retaining state across uninterruptible native work.
  priority: must
  stability: evolving

- id: simd_json.projection_execution.native_memory_baseline
  statement: Test builds shall prove document, parser, input, plan, slot, term-environment, operation, and retained-resource counts return to baseline after every binary and document success, failure, cancellation, caller-death, close, garbage-collection, and application-generation path.
  priority: must
  stability: evolving

- id: simd_json.projection_execution.scheduler_qualification
  statement: Large concurrent successful and failing projections shall preserve the accepted normal-scheduler heartbeat budget and shall not use dirty schedulers as the projection queue.
  priority: must
  stability: evolving

- id: simd_json.projection_execution.end_to_end_benchmark
  statement: Projection qualification shall compare complete select/2 work against Jason full decode plus equivalent lookups using predeclared fixtures and shall include validation, scheduling, parsing, traversal, result construction, cleanup, latency, throughput, BEAM and native allocation, retained binary memory, garbage collection, and scheduler latency.
  priority: must
  stability: evolving

- id: simd_json.projection_execution.sparse_allocation_advantage
  statement: Before qualification measurements run, the repository shall declare and then enforce a reproducible sparse-projection acceptance threshold demonstrating substantially lower BEAM allocation than Jason full materialization plus equivalent lookups.
  priority: must
  stability: evolving

- id: simd_json.projection_execution.preproduction_boundary
  statement: Milestone 2 shall continue to identify the Zigler-threaded runtime as pre-production and shall not claim the bounded admission pool, backpressure, or public telemetry assigned to Milestone 4.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.projection_execution.binary_operation_lifetime
  covers:
    - simd_json.projection_execution.threaded_projection
    - simd_json.projection_execution.one_correlated_operation
    - simd_json.projection_execution.binary_temporary_document
    - simd_json.projection_execution.native_memory_baseline
  given:
    - Valid, malformed, missing-path, and allocation-failing large binary inputs
  when:
    - Each is projected and the caller retains only the terminal result
  then:
    - One correlated worker owns the complete temporary native graph
    - Every temporary allocation is gone before return or orphan cleanup
    - A successful result remains valid independently of the source

- id: simd_json.projection_execution.document_one_shot
  covers:
    - simd_json.projection_execution.owner_first_admission
    - simd_json.projection_execution.exclusive_document_selection
    - simd_json.projection_execution.committed_consumption
    - simd_json.projection_execution.preadmission_nonconsumption
  given:
    - Fresh documents and both invalid and valid projections
  when:
    - Invalid preflight, successful traversal, missing-path failure, malformed-source failure, and a second owner selection are attempted
  then:
    - Preflight rejection leaves the document fresh
    - Every worker-committed attempt leaves it consumed
    - A later selection returns cursor_consumed without native cursor access
    - Owner close remains idempotent

- id: simd_json.projection_execution.non_owner_and_close_race
  covers:
    - simd_json.projection_execution.owner_first_admission
    - simd_json.projection_execution.generation_and_resource_retention
    - simd_json.projection_execution.close_interlock
  given:
    - An owner selection in each cancellation boundary and the document term held by another process
  when:
    - The other process attempts selection and cleanup or shutdown begins
  then:
    - The other process receives not_owner without state disclosure or mutation
    - Active work retains valid state until cancellation and cleanup reach a safe boundary
    - No stale result is delivered after generation invalidation

- id: simd_json.projection_execution.submission_rejection_retry
  covers:
    - simd_json.projection_execution.preadmission_nonconsumption
    - simd_json.projection_execution.one_correlated_operation
  given:
    - A fresh document and a test seam that rejects projection submission before worker admission
  when:
    - Submission fails and the seam is then disabled
  then:
    - The failed call returns the stable native failure without fallback execution
    - Its reservation is safely rolled back
    - A later valid owner projection can consume the same fresh document

- id: simd_json.projection_execution.caller_death_and_cancellation
  covers:
    - simd_json.projection_execution.generation_and_resource_retention
    - simd_json.projection_execution.close_interlock
    - simd_json.projection_execution.cancellation_boundaries
    - simd_json.projection_execution.native_memory_baseline
  given:
    - Binary and document projections paused at each defined cancellation boundary
  when:
    - The caller dies or shutdown requests cancellation
  then:
    - Work stops at the next safe boundary without delivering an orphan result
    - Uninterruptible native state remains retained until safe
    - All counters return to baseline exactly once

- id: simd_json.projection_execution.large_projection_responsiveness
  covers:
    - simd_json.projection_execution.threaded_projection
    - simd_json.projection_execution.scheduler_qualification
    - simd_json.projection_execution.preproduction_boundary
  given:
    - Independent BEAM heartbeats and concurrent large valid, malformed, missing-path, and cancelled sparse projections
  when:
    - The qualification profile records worker entry and normal and dirty scheduler utilization
  then:
    - Heartbeat latency remains within the accepted budget
    - Input-dependent work is observed only on the threaded path
    - Results make no production admission-control claim

- id: simd_json.projection_execution.jason_sparse_benchmark
  covers:
    - simd_json.projection_execution.end_to_end_benchmark
    - simd_json.projection_execution.sparse_allocation_advantage
  given:
    - Predeclared small, medium, and large sparse-projection fixtures, selected paths, environment, sample policy, and allocation threshold
  when:
    - SimdJson.select/2 is compared with Jason.decode/1 plus equivalent lookups end to end
  then:
    - The report includes every required timing, scheduler, garbage-collection, retained-memory, and allocation dimension
    - The declared BEAM-allocation advantage passes without excluding validation, scheduling, result construction, or cleanup cost
```

## Evidence Inventory

```yaml
- kind: test_file
  target: test/simd_json/select_test.exs
  covers:
    - simd_json.projection_execution.preadmission_nonconsumption
    - simd_json.projection_execution.binary_operation_lifetime
    - simd_json.projection_execution.document_one_shot
    - simd_json.projection_execution.submission_rejection_retry

- kind: test_file
  target: test/native/threaded_projection_integration_test.exs
  covers:
    - simd_json.projection_execution.threaded_projection
    - simd_json.projection_execution.one_correlated_operation
    - simd_json.projection_execution.generation_and_resource_retention
    - simd_json.projection_execution.close_interlock
    - simd_json.projection_execution.cancellation_boundaries
    - simd_json.projection_execution.native_memory_baseline

- kind: test_file
  target: test/native/projection_document_lifecycle_test.exs
  covers:
    - simd_json.projection_execution.owner_first_admission
    - simd_json.projection_execution.exclusive_document_selection
    - simd_json.projection_execution.committed_consumption
    - simd_json.projection_execution.preadmission_nonconsumption
    - simd_json.projection_execution.close_interlock
```

## Required Closure Evidence

The executable command below runs threaded admission, correlation, owner-first,
one-shot consumption, submission rollback, generation, close, caller-death,
cancellation, shutdown, baseline, scheduler, and end-to-end Jason comparison
evidence. The benchmark fixtures and threshold were committed before the
accepted measurement record.

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/qualify_projection_execution.sh
  execute: true
  covers:
    - simd_json.projection_execution.threaded_projection
    - simd_json.projection_execution.one_correlated_operation
    - simd_json.projection_execution.owner_first_admission
    - simd_json.projection_execution.exclusive_document_selection
    - simd_json.projection_execution.committed_consumption
    - simd_json.projection_execution.preadmission_nonconsumption
    - simd_json.projection_execution.generation_and_resource_retention
    - simd_json.projection_execution.binary_temporary_document
    - simd_json.projection_execution.close_interlock
    - simd_json.projection_execution.cancellation_boundaries
    - simd_json.projection_execution.native_memory_baseline
    - simd_json.projection_execution.scheduler_qualification
    - simd_json.projection_execution.end_to_end_benchmark
    - simd_json.projection_execution.sparse_allocation_advantage
    - simd_json.projection_execution.preproduction_boundary
    - simd_json.projection_execution.binary_operation_lifetime
    - simd_json.projection_execution.document_one_shot
    - simd_json.projection_execution.non_owner_and_close_race
    - simd_json.projection_execution.submission_rejection_retry
    - simd_json.projection_execution.caller_death_and_cancellation
    - simd_json.projection_execution.large_projection_responsiveness
    - simd_json.projection_execution.jason_sparse_benchmark
```
