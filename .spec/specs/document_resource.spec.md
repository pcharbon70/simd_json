# Document Resource

Milestone 5 Phase 4 confines eager decode documents, materializers, results,
and graph frames to one pool job and releases them on every terminal path.

Milestone 5 Phase 5 exposes only decoded values and shared errors; no temporary
decode document or owner is added to the public resource surface.

ABI v4 adds no document ownership transfer: an opaque decode materializer is
operation-scoped and its caller retains the document through destruction.

Milestone 5 Phase 1 adds native-free decode preflight only and does not create,
retain, consume, or transition a document resource.

Milestone 4 Phase 5 retains documents in queued and running pool jobs. Cleanup
stops later admission and native state outlives the final retained job.

Milestone 4 Phase 4 established the serialization interlock now used by Phase
5 production jobs without weakening document ownership or destruction.

Current-truth contract for the opaque `SimdJson.Document` resource, padded input memory, process ownership, and exactly-once native cleanup required by Milestone 1.

## Intent

This subject prevents use-after-free, unsafe simdjson over-read, double destruction, and incoherent cross-process access while leaving a stable parent-resource model for later cursor and streaming milestones.

Phases 1 through 3 contribute the vendored parser, private opaque C
parser/document handles, Zig-owned aligned padded input, registered opaque BEAM
resource storage, monotonic lifecycle primitives, reverse rollback, parent
retention helpers, and bounded test-only accounting. Phase 4 now retains input
through a private environment, constructs the padded copy and native handles on
a Zigler worker, publishes an internal parsed document resource, and uses a
threaded explicit/orphan cleanup operation. GC callbacks now detach an
intrusive control block into a cleanup-only dispatcher, failed handoff retains
ownership for retry, and concurrent internal cleanup joins exactly-once native
destruction. Phase 5 publishes that resource only inside
an opaque redacted document, check its immutable owner before both open and
closed lifecycle state, and give the owner an idempotent close that waits for
threaded destruction. Public documentation and API allowlists preserve that
authority model. Its public integration matrix now drops the original BEAM
input before threaded native revalidation, crosses open and closed terms between
processes, queues repeated owner closes, isolates concurrent owners, and returns
explicit and GC cleanup batches to native gauge baselines. Phase 6 Section 6.1
now runs the Zig ownership harness plus the actual threaded/public NIF corpus
under AddressSanitizer and UndefinedBehaviorSanitizer, while release inspection
proves test accounting stays absent. Section 6.2 executes seeded cancellation,
submission failure, owner/non-owner close,
dropped-term, GC, and application-generation batches; every batch returns all
live native gauges to baseline and the mixed batch counts exactly one cleanup
per opened document. Section 6.3 reconciles the ownership and operations
documentation and activates this subject against executable qualification.

Milestone 2 Phase 1 exercises a genuine open document only through the private
BEAM preflight seam. Invalid projection terms create no native admission,
request, allocation, generation change, lifecycle transition, or cursor state;
the accepted Milestone 1 resource graph and close behavior therefore remain
unchanged until projection admission is implemented in a later phase.
Milestone 2 Phase 2 adds an operation-scoped projection plan type beside, not
inside, the document resource. Plan conformance never publishes a plan as a
BEAM resource, never admits against a document, and does not change document,
parser, padded-input, parent-retention, generation, or cleanup ownership.
Milestone 2 Phase 3 claims the underlying C++ cursor defensively only in native
harnesses. Phase 4 now adds the resource-level single-use projection state and
an admitted-operation interlock beside the unchanged lifecycle. Owner-first
reservation, pre-worker rollback, committed consumption, close cancellation,
generation validation, and retained-document conversion are exercised through
private integration seams. Binary projection reuses the same owned padded
constructor in an unpublished worker-local document graph. Milestone 2 Phase 5
now routes public `select/2` document values through a bounded genuine-resource
and owner/lifecycle check before that reservation. The opaque public document
representation remains unchanged, exposes no projection resource or state, and
preserves owner-first rejection, one-shot consumption, close interlock, and
exactly-once cleanup through the real public boundary.
Milestone 2 Phase 6 adds seeded binary/document caller death at all six
projection boundaries, reachable failure checkpoints, retryable admission,
dropped result/document GC, cleanup-handoff retry, and application-generation
cycles. Every batch restores the full exposed document and projection graph to
baseline; standalone sanitizer accounting continues to own parser, node, and
key-byte detail.
Milestone 3 Phase 1 uses the existing bounded registered-resource check only to
classify a genuine document for private stream preflight. It deliberately
defers owner, closed, and one-shot failures until future reduction, retains the
opaque document term without reserving it, and proves fresh document lifecycle,
projection state, generation, admissions, coordinator state, and native gauges
do not change. No stream cursor or parent-retention graph exists yet.
Milestone 3 Phase 2 registers a private stream cursor resource that keeps the
genuine document resource before any future native dereference. Its rollback
and destructor destroy cursor-owned plan and target state before releasing the
parent. Genuine BEAM-resource tests and standalone Zig accounting prove
retain/release symmetry; no public stream operation or target traversal exists
yet.
Milestone 3 Phase 4 generalizes the one-shot state to permit exactly one
selecting or streaming reservation. Owner-first rejection reveals no state,
pre-worker rejection can roll streaming back to fresh, cursor access commits
consumed, and the private cursor retains the committed admission plus parent
until cursor-first teardown releases both. Binary fixtures retain the same
owned native graph without publishing a document resource.

Milestone 3 Phase 5 routes public document streams through the same owner-first stream reservation, retained cursor parent, consumed terminal state, and idempotent owner close proven by the private Phase 4 lifecycle.

Milestone 4 Phase 1 adds no native worker, queue, job, or resource transition.
It validates future finite capacity before coordinator startup; document input,
parser, cleanup, owner, generation, and one-shot lifecycle contracts remain
unchanged.

```spec-meta
id: simd_json.document_resource
kind: subsystem
status: active
verification_minimum_strength: executed
summary: Documents own padded input, parser state, lifecycle metadata, and single-process authority through one opaque BEAM resource.
surface:
  - native/**
  - lib/simd_json/**/*.ex
  - test/**/*document*
  - test/**/*resource*
  - docs/milestones/01-native-foundation.md
decisions:
  - simd_json.document_resource_and_buffer_ownership
  - simd_json.off_scheduler_native_execution
  - simd_json.owned_native_jobs_and_bounded_fifo
  - simd_json.monitored_delivery_and_resource_serialization
```

## Requirements

```spec-requirements
- id: simd_json.document_resource.opaque_handle
  statement: A document shall be represented by an opaque BEAM resource that exposes no native address, parser handle, input pointer, or cursor generation.
  priority: must
  stability: stable

- id: simd_json.document_resource.padded_owned_copy
  statement: Milestone 1 shall copy each accepted input binary into an aligned native allocation with the exact initialized padding required by the pinned simdjson release.
  priority: must
  stability: stable

- id: simd_json.document_resource.zero_copy_disabled
  statement: Milestone 1 shall provide no zero-copy input path unless a superseding accepted decision and platform-specific safety evidence authorize it.
  priority: must
  stability: stable

- id: simd_json.document_resource.complete_ownership
  statement: The document resource shall own its padded input, parser, On-Demand document, owner PID, generation, lifecycle state, and lifecycle synchronization for their complete native lifetimes.
  priority: must
  stability: stable

- id: simd_json.document_resource.single_owner
  statement: Only the process that opened a document shall operate on or close it, and possession of the resource term shall not transfer ownership.
  priority: must
  stability: stable

- id: simd_json.document_resource.lifecycle
  statement: A document shall move monotonically from open to closing to closed, with exactly one winner responsible for native cleanup.
  priority: must
  stability: stable

- id: simd_json.document_resource.idempotent_close
  statement: Owner calls to close shall join the shared cleanup operation and return :ok only after the resource is closed and all document-owned native allocations have been released exactly once.
  priority: must
  stability: stable

- id: simd_json.document_resource.reverse_destruction
  statement: Cleanup shall prevent new work, invalidate the generation, destroy the On-Demand document, destroy the parser, and release the padded input in dependency-safe order.
  priority: must
  stability: stable

- id: simd_json.document_resource.parent_retention
  statement: Every future child cursor resource shall retain its parent document resource rather than retain an unowned raw parent pointer.
  priority: must
  stability: stable

- id: simd_json.document_resource.deferred_large_cleanup
  statement: Potentially unbounded parser or input teardown shall execute off scheduler rather than inside an ordinary resource destructor callback.
  priority: must
  stability: stable

- id: simd_json.document_resource.test_accounting
  statement: Test builds shall expose bounded native allocation and destruction accounting sufficient to prove baseline recovery without exposing native addresses or input content.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.document_resource.input_lifetime
  covers:
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.complete_ownership
  given:
    - A valid JSON binary used to open a document
  when:
    - Every BEAM reference to the original input is dropped and garbage collection runs
  then:
    - The open native document remains valid
    - The parser reads only the logical input and initialized padding owned by the resource

- id: simd_json.document_resource.repeated_close
  covers:
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.reverse_destruction
  given:
    - One successfully opened document
  when:
    - Its owner calls close repeatedly and the BEAM later destroys the resource
  then:
    - Every close call returns :ok
    - The On-Demand document, parser, and input buffer are each released exactly once before close returns
    - Native sanitizer checks report no double free or use-after-free

- id: simd_json.document_resource.non_owner_rejection
  covers:
    - simd_json.document_resource.single_owner
  given:
    - A document opened by process A and its Elixir term sent to process B
  when:
    - Process B attempts a document operation or close
  then:
    - The call returns a structured not_owner error
    - The document lifecycle and generation do not change

- id: simd_json.document_resource.partial_open_failure
  covers:
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.reverse_destruction
  given:
    - Failure injected after each allocation step during open
  when:
    - Document construction aborts
  then:
    - Every completed allocation is released in dependency-safe order
    - No usable document resource is returned

- id: simd_json.document_resource.gc_cleanup
  covers:
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.deferred_large_cleanup
  given:
    - An open document whose owner does not call close
  when:
    - The resource becomes unreachable and garbage collection runs
  then:
    - Cleanup is admitted exactly once through the off-scheduler path
    - A normal scheduler does not synchronously perform unbounded teardown

- id: simd_json.document_resource.native_memory_baseline
  covers:
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.test_accounting
  given:
    - A recorded native allocation baseline
    - Batches of documents released by explicit close and by garbage collection
  when:
    - Every explicit close has returned and all admitted garbage-collection cleanup has completed
  then:
    - Document, parser, buffer, operation, and retained-resource counts return to baseline
    - Native leak and double-destruction checks remain clean
```

## Evidence Inventory

```yaml
- kind: test_file
  target: test/native/document_resource_registration_test.exs
  covers:
    - simd_json.document_resource.opaque_handle
    - simd_json.document_resource.complete_ownership
    - simd_json.document_resource.parent_retention

- kind: test_file
  target: test/native/zig_resource_test.exs
  covers:
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.zero_copy_disabled
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.partial_open_failure

- kind: test_file
  target: test/native/document_resource_policy_test.exs
  covers:
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.zero_copy_disabled
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime

- kind: test_file
  target: test/native/threaded_document_open_test.exs
  covers:
    - simd_json.document_resource.opaque_handle
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.complete_ownership
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.partial_open_failure

- kind: test_file
  target: test/native/threaded_teardown_test.exs
  covers:
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.gc_cleanup
    - simd_json.document_resource.native_memory_baseline

- kind: test_file
  target: test/simd_json/document_api_test.exs
  covers:
    - simd_json.document_resource.opaque_handle
    - simd_json.document_resource.single_owner
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.repeated_close
    - simd_json.document_resource.non_owner_rejection

- kind: test_file
  target: test/simd_json/phase_5_integration_test.exs
  covers:
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.single_owner
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.repeated_close
    - simd_json.document_resource.non_owner_rejection
    - simd_json.document_resource.native_memory_baseline

- kind: command
  target: bash scripts/native/run_zig_resource_tests.sh ordinary
  covers:
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.zero_copy_disabled
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.parent_retention
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.partial_open_failure

- kind: command
  target: bash scripts/native/run_zig_resource_tests.sh sanitizer
  covers:
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.zero_copy_disabled
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.partial_open_failure

- kind: command
  target: bash scripts/native/verify_release_symbols.sh
  covers:
    - simd_json.document_resource.test_accounting

- kind: command
  target: bash scripts/native/run_nif_sanitizer_tests.sh
  covers:
    - simd_json.document_resource.opaque_handle
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.complete_ownership
    - simd_json.document_resource.single_owner
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.repeated_close
    - simd_json.document_resource.non_owner_rejection
    - simd_json.document_resource.gc_cleanup
    - simd_json.document_resource.native_memory_baseline

- kind: test_file
  target: test/qualification/lifecycle_memory_qualification_test.exs
  covers:
    - simd_json.document_resource.single_owner
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.repeated_close
    - simd_json.document_resource.non_owner_rejection
    - simd_json.document_resource.gc_cleanup
    - simd_json.document_resource.native_memory_baseline

- kind: command
  target: bash scripts/ci/qualify_runtime.sh
  covers:
    - simd_json.document_resource.opaque_handle
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.zero_copy_disabled
    - simd_json.document_resource.complete_ownership
    - simd_json.document_resource.single_owner
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.parent_retention
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.repeated_close
    - simd_json.document_resource.non_owner_rejection
    - simd_json.document_resource.partial_open_failure
    - simd_json.document_resource.gc_cleanup
    - simd_json.document_resource.native_memory_baseline
```

## Required Closure Evidence

The executable resource-qualification command below supplies allocation-failure
injection, process-ownership, garbage-collection, repeated-close, native-memory
baseline, and sanitizer evidence for use-after-free, leaks, and double
destruction.

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/qualify_document_resource.sh
  execute: true
  covers:
    - simd_json.document_resource.opaque_handle
    - simd_json.document_resource.padded_owned_copy
    - simd_json.document_resource.zero_copy_disabled
    - simd_json.document_resource.complete_ownership
    - simd_json.document_resource.single_owner
    - simd_json.document_resource.lifecycle
    - simd_json.document_resource.idempotent_close
    - simd_json.document_resource.reverse_destruction
    - simd_json.document_resource.parent_retention
    - simd_json.document_resource.deferred_large_cleanup
    - simd_json.document_resource.test_accounting
    - simd_json.document_resource.input_lifetime
    - simd_json.document_resource.repeated_close
    - simd_json.document_resource.non_owner_rejection
    - simd_json.document_resource.partial_open_failure
    - simd_json.document_resource.gc_cleanup
    - simd_json.document_resource.native_memory_baseline
```
