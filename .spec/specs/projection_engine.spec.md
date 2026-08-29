# Projection Engine

Planned current-truth contract for the Milestone 2 prefix-sharing projection
plan, exception-safe private ABI, single guided traversal, and transactional
native result slots.

## Intent

This subject preserves simdjson's On-Demand advantage without exposing its
forward-only cursor. It ensures shared path prefixes are evaluated once, source
order never changes public results, unselected input is still validated, and no
BEAM terms are constructed for unrequested containers or values.

Phase 1 provides the engine's only accepted input: an opaque, deterministic
BEAM term containing declaration-order output slots and a first-seen table of
validated paths, with identical paths sharing one path slot. Phase 2 advances
the private compile-time contract to ABI version 2 while preserving the four
ABI v1 parser/document symbols and their 16-byte status. It adds fixed
descriptors, a distinct projection status, caller-owned typed result slots, an
opaque operation-scoped plan, and the reserved future execution signature.
Zig serializes only numeric slots and typed segments into temporary storage;
C++ validates the complete descriptor set, copies retained object keys, and
builds an immutable canonically ordered trie with shared prefixes and multiple
terminal slots. Independent C/Zig ordinary and sanitizer matrices cover
layouts, boundary fixtures, every injected constructor checkpoint, exception
containment, idempotent ownership, and release symbols. Phase 3 Sections 3.1
through 3.3 now dispatch decoded object keys in source order with
first-occurrence duplicate handling, advance arrays against ascending requested
indexes, produce exact typed slots, consume malformed selected and unselected
content, enforce the pinned depth bound, clear slots transactionally, check a
hidden cancellation probe, and record bounded execution diagnostics. Section
3.4 integration closure remains, and the subject intentionally stays planned
under its bootstrap exception until Milestone 2 qualification.

```spec-meta
id: simd_json.projection_engine
kind: subsystem
status: planned
summary: Milestone 2 compiles all requested paths into one native plan and evaluates them transactionally in one complete source-order traversal.
surface:
  - native/include/**
  - native/src/**
  - native/zig/**
  - test/**/*projection*
  - scripts/native/**/*projection*
  - docs/milestones/02-projection-api.md
decisions:
  - simd_json.native_stack_and_c_abi
  - simd_json.projection_api_and_validation
  - simd_json.prefix_sharing_projection_engine
```

## Requirements

```spec-requirements
- id: simd_json.projection_engine.prefix_sharing_plan
  statement: The complete validated projection shall compile into one immutable operation-scoped native tree that shares common object and array prefixes and allows multiple output slots at one terminal path.
  priority: must
  stability: stable

- id: simd_json.projection_engine.declaration_order_independence
  statement: Projection declaration order shall affect only output-key association and shall not control or constrain source traversal, missing-field detection, or result values.
  priority: must
  stability: stable

- id: simd_json.projection_engine.single_guided_traversal
  statement: One execution shall advance the On-Demand document once in source order, visit each shared prefix once, and shall not rewind, reparse, or perform an independent lookup for each requested path.
  priority: must
  stability: stable

- id: simd_json.projection_engine.complete_source_validation
  statement: A successful projection shall structurally consume and validate the complete logical JSON value, including unselected branches and content after the last selected value, without materializing those values, while rejecting input beyond the pinned 1,024-level native traversal bound.
  priority: must
  stability: stable

- id: simd_json.projection_engine.duplicate_json_key_policy
  statement: When an object repeats a requested key, the first occurrence in document order shall satisfy that path while later occurrences remain structurally consumed and validated without overwriting the result.
  priority: must
  stability: stable

- id: simd_json.projection_engine.scalar_only_materialization
  statement: The engine shall materialize native slots only for requested scalar terminals and shall skip unselected values and reject requested object or array terminals without constructing equivalent BEAM containers.
  priority: must
  stability: stable

- id: simd_json.projection_engine.typed_result_slots
  statement: Native traversal shall store each selected value in a fixed-layout tagged slot that preserves signed integer, unsigned integer, floating-point, boolean, null, and borrowed string-view distinctions until Zig conversion.
  priority: must
  stability: stable

- id: simd_json.projection_engine.transactional_conversion
  statement: BEAM result construction shall begin only after complete traversal and slot validation succeed, shall copy borrowed strings before their document lifetime ends, and shall discard every partial term environment on failure or cancellation.
  priority: must
  stability: stable

- id: simd_json.projection_engine.private_abi_v2
  statement: Private ABI version 2 shall preserve Milestone 1 parser and document behavior while exposing only fixed-width descriptors, an opaque projection plan with matching destructor, one execution function, typed caller-owned result slots, and stable projection statuses.
  priority: must
  stability: evolving

- id: simd_json.projection_engine.exception_and_failure_cleanup
  statement: Every projection C ABI function shall contain all C++ exceptions and release plan nodes, copied key bytes, slots, and partial traversal state exactly once on construction, execution, conversion, allocation, and cancellation failures.
  priority: must
  stability: stable

- id: simd_json.projection_engine.single_beam_boundary
  statement: A complete projection shall cross the BEAM/NIF request boundary once and shall not invoke a NIF per field, path, segment, or result slot.
  priority: must
  stability: stable

- id: simd_json.projection_engine.internal_phase_timing
  statement: Test and diagnostic builds shall record redacted compilation, traversal, and term-construction durations without exposing a public telemetry API or source content in Milestone 2.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.projection_engine.shared_prefix_and_order
  covers:
    - simd_json.projection_engine.prefix_sharing_plan
    - simd_json.projection_engine.declaration_order_independence
    - simd_json.projection_engine.single_guided_traversal
  given:
    - Paths sharing object and array prefixes, including two output keys for one identical path
    - Projection declaration order opposite to JSON object and array-index order
  when:
    - The plan compiles and executes
  then:
    - Every shared prefix and identical terminal is evaluated once
    - Every output slot receives the value associated with its caller key
    - No rewind or per-path reparse occurs

- id: simd_json.projection_engine.object_array_walk
  covers:
    - simd_json.projection_engine.single_guided_traversal
    - simd_json.projection_engine.scalar_only_materialization
    - simd_json.projection_engine.typed_result_slots
  given:
    - Nested objects and arrays with selected low and high indexes and very large unselected subtrees
  when:
    - The projection executes
  then:
    - Objects and arrays advance once in source order
    - Requested scalars populate correctly typed slots
    - Unselected and container values produce no corresponding BEAM tree

- id: simd_json.projection_engine.invalid_unselected_content
  covers:
    - simd_json.projection_engine.complete_source_validation
    - simd_json.projection_engine.transactional_conversion
  given:
    - Malformed JSON before, inside, and after selected paths, including malformed content in an unselected branch
  when:
    - Projection runs
  then:
    - Every source returns a parse failure at a logical byte offset when available
    - No partial result map or selected value escapes

- id: simd_json.projection_engine.duplicate_object_keys
  covers:
    - simd_json.projection_engine.duplicate_json_key_policy
  given:
    - Requested object keys repeated at root and nested depths
  when:
    - The projection succeeds
  then:
    - The first occurrence in document order supplies each requested value
    - Later occurrences are validated but never overwrite completed slots

- id: simd_json.projection_engine.transactional_slot_failure
  covers:
    - simd_json.projection_engine.typed_result_slots
    - simd_json.projection_engine.transactional_conversion
    - simd_json.projection_engine.exception_and_failure_cleanup
  given:
    - Failure injection after each plan allocation, traversal slot, string copy, and BEAM conversion step
  when:
    - Each failure is triggered after earlier slots have succeeded
  then:
    - No partial public result is delivered
    - Every owned plan, byte arena, slot, term environment, and retained document reference is released exactly once

- id: simd_json.projection_engine.abi_v2_conformance
  covers:
    - simd_json.projection_engine.private_abi_v2
    - simd_json.projection_engine.exception_and_failure_cleanup
  given:
    - An independent C11 harness using only the version 2 header
  when:
    - It compiles, executes, cancels, injects exceptions and allocation failures, and destroys null, partial, and complete projection plans
  then:
    - Only documented fixed-layout values and stable statuses cross the ABI
    - No exception escapes and every constructor has one matching cleanup path
    - Release symbols contain only the versioned allowlist

- id: simd_json.projection_engine.one_boundary_with_timing
  covers:
    - simd_json.projection_engine.single_beam_boundary
    - simd_json.projection_engine.internal_phase_timing
  given:
    - A projection containing many fields and shared prefixes
  when:
    - Boundary and timing diagnostics are enabled in a test build
  then:
    - Exactly one request admission and one terminal delivery are observed
    - Compilation, traversal, and construction timings are bounded and redacted
    - No diagnostic or timing function appears in the release public API
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed C and Zig
plan/traversal tests, ordinary and sanitizer conformance, failure injection,
full-input malformed corpora, duplicate-key fixtures, shared-prefix counters,
boundary accounting, release symbol inspection, and result-slot conversion
tests.

## Exceptions

```spec-exceptions
- id: simd_json.projection_engine.milestone_02_bootstrap
  covers:
    - simd_json.projection_engine.prefix_sharing_plan
    - simd_json.projection_engine.declaration_order_independence
    - simd_json.projection_engine.single_guided_traversal
    - simd_json.projection_engine.complete_source_validation
    - simd_json.projection_engine.duplicate_json_key_policy
    - simd_json.projection_engine.scalar_only_materialization
    - simd_json.projection_engine.typed_result_slots
    - simd_json.projection_engine.transactional_conversion
    - simd_json.projection_engine.private_abi_v2
    - simd_json.projection_engine.exception_and_failure_cleanup
    - simd_json.projection_engine.single_beam_boundary
    - simd_json.projection_engine.internal_phase_timing
    - simd_json.projection_engine.shared_prefix_and_order
    - simd_json.projection_engine.object_array_walk
    - simd_json.projection_engine.invalid_unselected_content
    - simd_json.projection_engine.duplicate_object_keys
    - simd_json.projection_engine.transactional_slot_failure
    - simd_json.projection_engine.abi_v2_conformance
    - simd_json.projection_engine.one_boundary_with_timing
  reason: The Milestone 2 native projection engine does not exist yet; remove this exception and replace it with executed plan, traversal, ABI, failure-cleanup, boundary, sanitizer, and full-source-validation evidence before activation.
```
