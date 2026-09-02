# Phase 3 — Forward-Only Array Traversal and Native Batches

Back to plan: [README](./README.md)

- [x] 3 Phase - Locate the target array once, advance it monotonically, reuse
  one projection plan per row, and produce transactional row-and-byte-bounded
  native batches.

  This phase implements the core streaming engine below the NIF boundary.
  Cursor frames survive batch boundaries, source order is preserved, exact
  end-of-array is returned with the final request, and full consumption
  validates enclosing input. C and Zig harnesses inspect native batches;
  threaded BEAM reduction begins in Phase 4.

  Contract focus:

  - `simd_json.stream_cursor.single_target_lookup`
  - `simd_json.stream_cursor.forward_only_rows`
  - `simd_json.stream_cursor.projection_plan_reuse`
  - `simd_json.stream_cursor.row_count_bound`
  - `simd_json.stream_cursor.encoded_byte_bound`
  - `simd_json.stream_cursor.transactional_batch`
  - `simd_json.stream_cursor.copied_row_values`
  - `simd_json.stream_cursor.exact_done_detection`
  - `simd_json.stream_cursor.complete_consumption_validation`
  - `simd_json.stream_cursor.indexed_status`
  - `simd_json.stream_cursor.batch_boundary`

## 3.1 Section — Target Location and Forward Row Traversal

- [x] 3.1 Section - Resolve the root or nested target once and preserve all
  traversal frames needed to advance rows and later validate enclosing input.

  This section makes each array element a single source-order event and keeps
  Milestone 2 path, duplicate-key, depth, and parse semantics consistent.

  - [x] 3.1.1 Task - Locate and validate the target array.

    The task consumes one validated target path without materializing skipped
    prefixes or publishing a cursor on failure.

    - [x] 3.1.1.1 Subtask - Require a top-level array for `path: []` and otherwise traverse object and array segments once using existing UTF-8, unsigned-index, first-duplicate, depth-limit, and logical-offset rules.
    - [x] 3.1.1.2 Subtask - Structurally consume unselected prefix siblings without constructing BEAM values and retain enclosing iterator frames required after the target array ends.
    - [x] 3.1.1.3 Subtask - Return stable missing-field, index, incorrect-type, parse, range, cancellation, allocation, or internal status before a cursor becomes ready.
    - [x] 3.1.1.4 Subtask - Count target execution entries and prove setup performs one lookup with no rewind, document reparse, independent lookup per segment, or target-array materialization.

  - [x] 3.1.2 Task - Advance target rows monotonically.

    The task preserves zero-based source index and cursor position across
    multiple batch calls.

    - [x] 3.1.2.1 Subtask - Consume each array element at most once, increment the checked 64-bit source index only for committed element advancement, and retain the next element for a later byte-limited batch when necessary.
    - [x] 3.1.2.2 Subtask - Preserve source order independent of projection output-slot order, batch boundary, string sizes, consumer speed, or future BEAM list construction.
    - [x] 3.1.2.3 Subtask - Reject repeated advance from running, failed, cancelled, done, and closed states without touching the parser or changing the last committed index.

## 3.2 Section — Reusable Projection and Bounded Batch Storage

- [x] 3.2 Section - Apply one compiled Milestone 2 projection to each row and
  stop every batch at both its row and encoded-byte limit.

  This section amortizes plan compilation while preserving transactional scalar
  slots, copied strings, exact keys, and checked allocation arithmetic.

  - [x] 3.2.1 Task - Reuse the row projection engine.

    The task executes the accepted prefix-sharing traversal relative to one
    element root with no alternate field matcher or per-field native call.

    - [x] 3.2.1.1 Subtask - Compile the complete fields plan once at cursor construction and retain its immutable nodes and copied key arena through every batch.
    - [x] 3.2.1.2 Subtask - Reset fresh typed result slots per row, execute shared and identical paths once, and preserve first duplicate keys, scalar tags, numeric fidelity, and container-terminal rejection.
    - [x] 3.2.1.3 Subtask - Structurally validate unselected content within every processed row without constructing maps, lists, keys, or values for it.
    - [x] 3.2.1.4 Subtask - Count one plan construction, one projection execution per attempted row, and zero NIF/ABI entries per field, segment, slot, or yielded value.

  - [x] 3.2.2 Task - Enforce row-count and encoded-byte bounds.

    The task calculates every fixed and variable batch cost before committing
    storage and makes a single oversized row a stable failure.

    - [x] 3.2.2.1 Subtask - Define the ABI v3 encoded-byte formula for row descriptors, typed slots, copied string bytes, and all variable result storage and test it with checked addition and multiplication.
    - [x] 3.2.2.2 Subtask - Reserve fixed row/slot storage before traversal, check each selected string before copy, and publish no count or byte value greater than configured capacity.
    - [x] 3.2.2.3 Subtask - Stop before a non-fitting later row, preserve it as the next request's first row, and avoid duplicate traversal, output, or source-index increment.
    - [x] 3.2.2.4 Subtask - Return `batch_too_large` with the row index when one row cannot fit an empty batch and release every partial descriptor, slot, and copied byte.

  - [x] 3.2.3 Task - Make each native batch transactional.

    The task publishes a complete row sequence only after all included rows and
    batch metadata are valid.

    - [x] 3.2.3.1 Subtask - Initialize every row and slot to explicit unset state and commit a batch only when all rows have complete scalar results and checked encoded-byte accounting.
    - [x] 3.2.3.2 Subtask - On row path/type/range, parse, size, allocation, internal, or cancellation failure, clear borrowed views and discard every row and copied string in the current batch.
    - [x] 3.2.3.3 Subtask - Convert native rows into source-ordered complete map terms only after native batch success, copying strings before any source view expires.
    - [x] 3.2.3.4 Subtask - Record bounded target, plan, row, batch, byte, phase-time, cancellation, and boundary counts in test builds without source or caller content.

## 3.3 Section — Completion, Indexed Failure, and Cleanup

- [x] 3.3 Section - Detect end in the final useful request, validate complete
  documents on full consumption, and return stable indexed failure without
  leaking partial batch state.

  This section distinguishes natural done from explicit early halt and freezes
  the native status behavior Phase 4 must translate.

  - [x] 3.3.1 Task - Implement exact terminal detection and final validation.

    The task handles empty, partial-final, and full-final batches without a
    separate probe call.

    - [x] 3.3.1.1 Subtask - Return empty rows plus done for an empty target array and rows plus done for partial and exact-multiple final batches from the request that observes array end.
    - [x] 3.3.1.2 Subtask - After natural target end, unwind retained enclosing frames and structurally validate remaining object fields, array elements, top-level termination, and trailing whitespace before committing done.
    - [x] 3.3.1.3 Subtask - Fail the current final batch when enclosing or trailing input is malformed, even if every target row and field slot was already filled.
    - [x] 3.3.1.4 Subtask - Keep an explicit close-without-finish path that releases current state without scanning remaining rows or claiming complete-source validation.

  - [x] 3.3.2 Task - Report deterministic row and field context.

    The task preserves safe diagnostic identity across native status and later
    Elixir translation.

    - [x] 3.3.2.1 Subtask - Attach the checked zero-based source index to row-specific missing, index, type, range, parse, oversized, allocation, and cancellation statuses when known.
    - [x] 3.3.2.2 Subtask - Attach an optional failing output slot only for projection-specific row failures and use unavailable sentinels for target, enclosing, or non-row failures.
    - [x] 3.3.2.3 Subtask - Preserve only logical offsets and bounded numeric upstream diagnostics; never store source excerpts, decoded keys, selected values, caller paths, or exception text.

  - [x] 3.3.3 Task - Contain failure and cancellation at every native edge.

    The task ensures no batch or parent resource becomes invalid while an
    uninterruptible native operation can still dereference it.

    - [x] 3.3.3.1 Subtask - Check cancellation before lookup and batch work, between elements and bounded projection units, before/during conversion, before final validation, and before delivery.
    - [x] 3.3.3.2 Subtask - Catch all C++ exception families in cursor and next-batch functions and unwind cursor frames, row storage, slots, strings, plan, and parent retention in dependency-safe order.
    - [x] 3.3.3.3 Subtask - Inject failure at every allocation and transition edge and require no success count, done state, string view, or row term escapes a failing call.

## 3.4 Section — Phase 3 Integration Tests

- [x] 3.4 Section - Prove target traversal, source ordering, plan reuse,
  row/byte bounds, exact done, full validation, indexed failures,
  cancellation, and cleanup through ordinary and sanitizer native harnesses.

  This section closes the native batch engine before it can operate on a
  threaded BEAM stream.

  - [x] 3.4.1 Task - Run the functional cursor and batch corpus.

    The task covers topology, boundaries, scalar values, Unicode, duplicate
    keys, large skipped content, and enclosing document shapes.

    - [x] 3.4.1.1 Subtask - Execute root and nested targets, empty/small/exact/large arrays, one-row and maximum-row batches, shared/identical field paths, mixed object/array segments, and every scalar type.
    - [x] 3.4.1.2 Subtask - Exercise byte limits around fixed and string costs, embedded NUL and Unicode strings, huge single values, duplicate keys, deep valid nesting, and large unselected row/enclosing subtrees.
    - [x] 3.4.1.3 Subtask - Verify stable target and row missing/index/type/range/UTF-8/EOF/invalid/batch-too-large behavior with exact source indexes, slots, offsets, and atomic batch results.
    - [x] 3.4.1.4 Subtask - Assert one target lookup, one plan compile, exact row executions and batch boundaries, no extra done probe, and no per-field/segment native entry.

  - [x] 3.4.2 Task - Run validation and failure-cleanup gates.

    The task attacks every place cursor state, borrowed input, or early row
    results could escape after failure.

    - [x] 3.4.2.1 Subtask - Place malformed syntax before the target, inside early and late rows, after exact batch boundaries, in unselected content, and after the target; require the correct failing batch and no false done.
    - [x] 3.4.2.2 Subtask - Inject cancellation and allocation failure across lookup, plan, row traversal, byte reservation, copy, conversion, final validation, and destruction; require status and full baseline recovery.
    - [x] 3.4.2.3 Subtask - Run ordinary, AddressSanitizer, and UndefinedBehaviorSanitizer cursor suites with guard-page, parent-retention, oversized-string, repeated-state, and borrowed-view lifetime fixtures.
    - [x] 3.4.2.4 Subtask - Run ABI v1/v2/v3, projection engine, document resource, and all Milestone 1/2 regressions, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 3 complete.
