# Document Resource

Current-truth contract for the opaque `SimdJson.Document` resource, padded input memory, process ownership, and exactly-once native cleanup required by Milestone 1.

## Intent

This subject prevents use-after-free, unsafe simdjson over-read, double destruction, and incoherent cross-process access while leaving a stable parent-resource model for later cursor and streaming milestones.

Phase 1 currently contributes only the vendored parser and an internal
build-smoke NIF beneath this subject's broad native surface. It allocates no
document state or BEAM resource; the bootstrap exception remains in force.

```spec-meta
id: simd_json.document_resource
kind: subsystem
status: planned
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

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed resource tests, allocation-failure injection, process-ownership tests, garbage-collection tests, repeated close races, native memory baseline checks, and sanitizer coverage for use-after-free, leaks, and double destruction.

## Exceptions

```spec-exceptions
- id: simd_json.document_resource.milestone_01_bootstrap
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
  reason: The opaque native resource is a planned Milestone 1 surface; remove this exception and replace it with executed lifecycle, ownership, failure-injection, scheduler, and sanitizer proof before activation.
```
