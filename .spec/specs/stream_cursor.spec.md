# Stream Cursor and Batch Engine

Planned current-truth contract for the Milestone 3 private ABI v3 array cursor,
forward-only target traversal, reusable per-row projection plan, bounded native
batches, and transactional result ownership.

## Intent

This subject preserves simdjson's On-Demand state across many useful batch
boundaries without exposing that state publicly. It ensures target lookup and
row traversal never rewind, every row reuses the accepted Milestone 2 engine,
and both row count and encoded bytes bound each native result.

Phase 1 implements only the native-free input to this future subsystem: one
opaque private term carries a validator-produced fields projection, exact root
or nested target, and checked row and encoded-byte limits. It creates no ABI v3
descriptor, cursor, plan owner, result storage, traversal, native entrypoint, or
diagnostic counter, so this subject remains planned under its complete
bootstrap exception.

Phase 2 now freezes private ABI v3 while preserving every ABI v1/v2 layout and
symbol. C++ and Zig construct one opaque cursor that copies normalized target
descriptors, borrows a document only beneath a retained genuine parent
resource, and transfers exactly one compiled projection plan. Independent C
and Zig ordinary/sanitizer matrices prove layout, state, limits, plan and parent
ownership, exception containment, allocation rollback, package inventory, and
release visibility. Target lookup, row traversal, populated batches, threaded
execution, and the public stream remain deliberately unimplemented.

Phase 3 now implements the private forward-only batch engine. It locates root
or nested target arrays once, retains enclosing On-Demand frames, reuses the
single transferred projection plan for every attempted row, and publishes only
complete row-and-byte-bounded batches with copied strings. Natural completion
unwinds and validates remaining enclosing content without rewind or reparse;
row failures carry checked indexes and optional slots, while cancellation and
injected native failures clear the complete in-flight batch. C and Zig ordinary
and sanitizer harnesses exercise bounds, exact completion, malformed trailing
content, diagnostics, allocation rollback, and exception containment. The
subject remains planned because threaded ownership and the public Enumerable
arrive in Phases 4 and 5, and its bootstrap exception closes only during Phase
6 activation.

```spec-meta
id: simd_json.stream_cursor
kind: subsystem
status: planned
summary: Milestone 3 advances one retained array cursor through transactional row-and-byte-bounded projection batches using private ABI v3.
surface:
  - native/include/**
  - native/src/**
  - native/zig/**
  - test/**/*stream*
  - test/**/*cursor*
  - test/**/*batch*
  - scripts/native/**/*stream*
  - docs/milestones/03-batched-array-streaming.md
decisions:
  - simd_json.native_stack_and_c_abi
  - simd_json.document_resource_and_buffer_ownership
  - simd_json.projection_api_and_validation
  - simd_json.prefix_sharing_projection_engine
  - simd_json.forward_only_batched_array_cursor
  - simd_json.stream_ownership_backpressure_and_lifetime
```

## Requirements

```spec-requirements
- id: simd_json.stream_cursor.private_abi_v3
  statement: Private ABI version 3 shall preserve all ABI v1 and v2 layouts and behavior while adding only fixed-width target descriptors, an opaque array cursor with matching destructor, one next-batch entry, bounded batch storage, stable status, row index, failing slot, count, byte, and done metadata.
  priority: must
  stability: evolving

- id: simd_json.stream_cursor.opaque_cursor
  statement: Native array position, enclosing traversal frames, iterator types, plan identity, source pointers, allocator state, and cursor handles shall remain opaque behind the C ABI and shall never cross the public Elixir boundary.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.parent_retention
  statement: A live stream cursor shall retain its genuine parent document resource, which retains parser and padded input, and shall never depend on an unretained raw parent pointer.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.single_target_lookup
  statement: Cursor construction shall locate the root or nested target array once in document order with the accepted path grammar, duplicate-key policy, depth bound, stable errors, and no rewind, reparse, or target materialization.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.forward_only_rows
  statement: Successful batch execution shall advance target elements monotonically in source order so every row is visited at most once and no request reparses an earlier element.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.projection_plan_reuse
  statement: The complete fields projection shall compile once per cursor and the same immutable prefix-sharing plan shall execute relative to every row with fresh transactional slots rather than recompiling or using a second path engine.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.row_count_bound
  statement: One next-batch execution shall produce no more than the configured batch_size rows and shall use checked arithmetic before allocating descriptors or result slots.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.encoded_byte_bound
  statement: One batch shall not exceed max_batch_bytes across ABI-defined row descriptors, typed slots, copied selected strings, and variable result storage; a row that cannot fit an empty batch shall fail with batch_too_large at its array index.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.transactional_batch
  statement: A batch shall become convertible only after every included row has a complete valid scalar slot set, and any parse, path, type, range, size, allocation, internal, or cancellation failure shall discard the complete in-flight batch.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.copied_row_values
  statement: Zig batch conversion shall preserve exact scalar types and output keys while copying every selected string before its source view can expire, leaving completed row maps independent of cursor and document lifetime.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.exact_done_detection
  statement: Empty, partial-final, and full-final batches shall return an explicit done state from the same request that discovers array end, including arrays whose size is an exact batch multiple, without a separate empty probe.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.complete_consumption_validation
  statement: Full stream completion shall structurally validate the complete logical JSON value, including unselected row content and content after the target array, while an explicitly halted stream shall close without validating the unconsumed remainder.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.indexed_status
  statement: Row-specific native failure shall carry a checked zero-based array index and optional failing output slot, while target or document failure shall use unavailable sentinels and every logical offset shall exclude padding.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.exception_and_failure_cleanup
  statement: Every ABI v3 function shall contain all C++ exceptions and release cursor frames, plan nodes, copied keys, row descriptors, slots, copied strings, arenas, and partial batch state exactly once after construction, execution, conversion, cancellation, or allocation failure.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.batch_boundary
  statement: Each native batch shall cross the BEAM request boundary once and shall not invoke a NIF per row, output field, path segment, scalar slot, or yielded map.
  priority: must
  stability: stable

- id: simd_json.stream_cursor.internal_diagnostics
  statement: Test and diagnostic builds shall record bounded redacted cursor, plan, row, batch, encoded-byte, phase-timing, and boundary counts without exposing source data, caller paths, native addresses, failure controls, or telemetry in release APIs.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.stream_cursor.abi_v3_conformance
  covers:
    - simd_json.stream_cursor.private_abi_v3
    - simd_json.stream_cursor.opaque_cursor
    - simd_json.stream_cursor.exception_and_failure_cleanup
  given:
    - Independent C11 and Zig harnesses using only the canonical ABI v3 header
  when:
    - They construct, advance, cancel, finish, and destroy null, partial, failed, done, and complete cursors with invalid descriptors and injected failures
  then:
    - Only documented fixed-layout data and stable statuses cross the ABI
    - ABI v1 and v2 conformance remains unchanged
    - No exception, internal pointer, leak, or double destruction escapes

- id: simd_json.stream_cursor.target_lookup_and_retention
  covers:
    - simd_json.stream_cursor.parent_retention
    - simd_json.stream_cursor.single_target_lookup
    - simd_json.stream_cursor.forward_only_rows
  given:
    - Root and deeply nested target arrays behind object and array segments
    - A parent document whose other BEAM references are dropped after cursor creation
  when:
    - Several batches advance the cursor
  then:
    - Target lookup occurs once with first duplicate-key behavior
    - Parent parser and input remain valid through the final cursor operation
    - No earlier source position is revisited

- id: simd_json.stream_cursor.reused_row_projection
  covers:
    - simd_json.stream_cursor.projection_plan_reuse
    - simd_json.stream_cursor.copied_row_values
    - simd_json.stream_cursor.batch_boundary
    - simd_json.stream_cursor.internal_diagnostics
  given:
    - Many object rows and a fields projection with shared and identical paths and every scalar type
  when:
    - Multiple native batches execute
  then:
    - One plan construction serves every projected row
    - One boundary occurs per batch and none per row or field
    - Every map preserves exact keys and copied values without source retention

- id: simd_json.stream_cursor.row_and_byte_boundaries
  covers:
    - simd_json.stream_cursor.row_count_bound
    - simd_json.stream_cursor.encoded_byte_bound
    - simd_json.stream_cursor.transactional_batch
  given:
    - Arrays and selected string sizes immediately below, at, and above row and encoded-byte limits
  when:
    - Batches are constructed
  then:
    - No success exceeds either configured limit
    - A non-fitting later row begins the next batch without duplication or omission
    - A row too large for an empty batch fails atomically at its source index

- id: simd_json.stream_cursor.exact_end_and_trailing_validation
  covers:
    - simd_json.stream_cursor.exact_done_detection
    - simd_json.stream_cursor.complete_consumption_validation
  given:
    - Empty, partial-batch, exact-multiple, and multi-batch target arrays
    - Valid and malformed enclosing content after the target array
  when:
    - Each cursor is fully consumed
  then:
    - Done is returned with the final useful request and no empty probe
    - Valid documents yield every row once
    - Malformed trailing content fails the final in-flight batch without false completion

- id: simd_json.stream_cursor.indexed_row_failure
  covers:
    - simd_json.stream_cursor.transactional_batch
    - simd_json.stream_cursor.indexed_status
  given:
    - A later row with missing field, bad index, wrong type, numeric range failure, malformed content, or conversion allocation failure
  when:
    - Its containing batch executes after earlier batches succeeded
  then:
    - Status identifies the deterministic source index and field slot when known
    - No row or copied string from the failing batch is published
    - Earlier cursor position is never replayed

- id: simd_json.stream_cursor.cancellation_and_cleanup_matrix
  covers:
    - simd_json.stream_cursor.parent_retention
    - simd_json.stream_cursor.exception_and_failure_cleanup
    - simd_json.stream_cursor.transactional_batch
  given:
    - Cancellation and allocation failure injected at target lookup, between rows, during projection, before and during conversion, and before delivery
  when:
    - Each boundary is triggered under ordinary and sanitizer harnesses
  then:
    - Work stops at the next safe boundary with no partial batch
    - Uninterruptible state remains retained until safe
    - Every cursor, plan, descriptor, slot, string, arena, and parent-retention count returns to baseline
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed target
traversal and row/byte boundary,
exact-end, complete-validation, indexed-status, cancellation, failure injection,
borrowed-string, threaded, public, and boundary-accounting
evidence.

## Exceptions

```spec-exceptions
- id: simd_json.stream_cursor.milestone_03_bootstrap
  covers:
    - simd_json.stream_cursor.private_abi_v3
    - simd_json.stream_cursor.opaque_cursor
    - simd_json.stream_cursor.parent_retention
    - simd_json.stream_cursor.single_target_lookup
    - simd_json.stream_cursor.forward_only_rows
    - simd_json.stream_cursor.projection_plan_reuse
    - simd_json.stream_cursor.row_count_bound
    - simd_json.stream_cursor.encoded_byte_bound
    - simd_json.stream_cursor.transactional_batch
    - simd_json.stream_cursor.copied_row_values
    - simd_json.stream_cursor.exact_done_detection
    - simd_json.stream_cursor.complete_consumption_validation
    - simd_json.stream_cursor.indexed_status
    - simd_json.stream_cursor.exception_and_failure_cleanup
    - simd_json.stream_cursor.batch_boundary
    - simd_json.stream_cursor.internal_diagnostics
    - simd_json.stream_cursor.abi_v3_conformance
    - simd_json.stream_cursor.target_lookup_and_retention
    - simd_json.stream_cursor.reused_row_projection
    - simd_json.stream_cursor.row_and_byte_boundaries
    - simd_json.stream_cursor.exact_end_and_trailing_validation
    - simd_json.stream_cursor.indexed_row_failure
    - simd_json.stream_cursor.cancellation_and_cleanup_matrix
  reason: Milestone 3 native streaming cursor does not exist; remove this exception and replace it with executed ABI, traversal, plan-reuse, bounds, validation, status, lifetime, boundary, failure-cleanup, and sanitizer evidence before activation.
```
