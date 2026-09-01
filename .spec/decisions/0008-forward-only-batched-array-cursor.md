---
id: simd_json.forward_only_batched_array_cursor
status: accepted
date: 2026-08-31
affects:
  - simd_json.stream_cursor
  - simd_json.streaming_api
  - simd_json.native_build_and_abi
  - simd_json.projection_engine
---

# Forward-Only Batched Array Cursor

## Context

Milestone 3 must advance a simdjson On-Demand array across multiple native
requests without reparsing the document, exposing a raw iterator, or invoking
the NIF once per row or field. The cursor must retain enough traversal state to
continue exactly where the previous batch ended, while the result of each
request remains independently owned and bounded.

The existing projection engine compiles shared paths and creates transactional
typed scalar slots for one source value. Streaming must apply that engine
relative to every array element rather than develop a second path matcher with
different duplicate-key, numeric, string, and error behavior.

## Decision

### Private ABI version 3

The canonical private C ABI advances to version 3. Every ABI v1 parser/document
and ABI v2 projection signature, status layout, symbol version, and behavior
remains unchanged. ABI v3 adds only fixed-layout streaming contracts:

- an opaque array-cursor constructor and matching null-safe destructor;
- a target-path descriptor using the existing typed segment representation;
- one `next_batch` execution entry;
- caller-owned batch descriptors, row descriptors, typed result slots, and a
  bounded copied-byte arena;
- stable cursor/batch statuses with optional failing field slot and zero-based
  array index;
- explicit row count, encoded-byte count, and `done` state in every successful
  response.

The C++ cursor borrows its document only while the upper Zig resource retains
the genuine parent document resource. It owns its iterator/traversal state and
any compiled projection plan or native storage retained across batches. No C++
iterator type, string view, allocator object, exception, pointer, or handle is
public in Elixir.

Every descriptor count, pointer/count pair, byte range, target segment,
projection slot, row index, limit, reserved field, addition, and multiplication
is validated before allocation or dereference. C11, C++17, and Zig compile-time
assertions freeze all sizes, alignments, offsets, tags, and sentinels. Release
symbol allowlists and independent ordinary/sanitizer conformance harnesses are
updated for ABI v3.

### Cursor creation and target location

The cursor locates the target array once, in source order, when reduction
starts. An empty target path requires the top-level value to be an array. A
non-empty target path uses the Milestone 2 object/index segment grammar,
first-occurrence duplicate object-key policy, logical byte offsets, depth
limit, and structural skipping behavior.

Target lookup never rewinds or reparses. A missing field, out-of-range index,
wrong intermediate type, non-array target, malformed source, numeric overflow,
or cancellation returns one stable status before a cursor becomes usable. A
document whose native cursor has been claimed remains consumed even when target
location fails.

The cursor retains the traversal frames needed to finish enclosing objects and
arrays after the target array ends. A fully consumed stream succeeds only after
the complete logical JSON document, including content following the target
array and trailing whitespace, has been structurally validated. Early halt is
the deliberate exception: it closes at the current position and does not scan
the remaining target array or enclosing document.

### Per-row projection reuse

The normalized `:fields` projection compiles once when the cursor is created.
Every array element executes that same immutable prefix-sharing plan relative
to the element root. The engine preserves declaration-order independence,
first duplicate-key wins, scalar-only terminals, exact numeric tags, and no
atom creation.

Plan topology and copied object-key bytes are reused; result slots and row
state are reset transactionally for each element. No row reparses the target
path, recompiles the plan, or performs an independent native call per field.
Internal test accounting must distinguish one cursor construction, one plan
construction, N batch executions, and the actual row projection count.

Rows stay in source-array order. A row projection failure reports that row's
zero-based index plus the failing caller field slot when available. It does not
skip the row, synthesize defaults, or continue with later elements.

### Bounded batch construction

One `next_batch` call constructs at most the configured `batch_size` rows and
never exceeds `max_batch_bytes` of encoded native output. Encoded bytes include
fixed row/slot descriptors, copied selected string bytes, and all other
variable batch-result storage defined by ABI v3. Input, parser, cursor, and
compiled-plan storage are separately retained cursor state and are reported in
memory qualification.

Before starting a row, checked arithmetic reserves its fixed descriptor and
slot cost. Selected string bytes are copied only after their sizes are checked.
If the next row would exceed the byte limit after at least one row is complete,
the batch stops before that row and leaves it for the next request. If one row
cannot fit in an empty batch, the operation returns `:batch_too_large` with its
array index and discards all partial row storage.

A successful batch is atomic. BEAM conversion begins only after every row in
that batch has a complete valid slot set and the batch status is final. Parse,
path, type, numeric, byte-limit, allocation, internal, or cancellation failure
discards all rows and copied bytes belonging to the current request.

The batch container is initially a proper list of row maps in source order.
Zig constructs fresh strings and complete maps in an operation-owned private
environment, then transfers one complete bounded batch at the generated join
boundary. The Elixir enumerable yields those existing maps without another
native crossing.

### End-of-array and validation state

The cursor detects array end while executing the current request. A partial
final batch returns its rows with `done: true` after final structural validation
succeeds. When the array length is an exact multiple of `batch_size`, the full
final batch also returns `done: true`; no empty probe request is required solely
to discover completion.

An empty target array returns an empty batch with `done: true`. Once done, the
cursor cannot advance again; internal repeated-next calls return a stable done
state without parser access. Closing done, cancelled, failed, or already closed
cursors is idempotent at the owning layer.

### Cancellation and failure containment

Cancellation is checked before target lookup, before each batch, between array
elements, between bounded projection traversal units, before each row and batch
conversion chunk, and before delivery. An uninterruptible simdjson call retains
the document, plan, batch, and operation until its next safe boundary.

Every ABI v3 function catches known simdjson errors, allocation failures,
standard exceptions, and unknown exceptions. Cursor construction and batch
failure unwind through dependency-safe, non-recursive cleanup. Test builds may
expose bounded counts, topology hashes, row indexes, byte counts, and phase
timings, but never source bytes, selected values, caller paths, native
addresses, or public diagnostic entrypoints.

## Consequences

Milestone 3 Phase 2 implementation checkpoint: private ABI v3 layouts, cursor
and plan ownership, genuine parent-resource retention, stable state validation,
symbol versioning, and ordinary/sanitizer C and Zig conformance are implemented.
The reserved batch entry performs no array traversal or row production; those
parts of this decision remain assigned to later phases.

The native plan and array position survive across batches, so boundary overhead
scales with batches rather than rows or fields. Complete consumption retains
the existing full-source validation guarantee, while early termination avoids
work the caller explicitly no longer demands.

The cursor holds the input and parser for the complete reduction. This is
bounded by source size but can be large, so deterministic halt cleanup and
native-memory qualification are required even though output batches are
strictly bounded.

ABI v3 expands the private conformance surface and invalidates prior native
qualification fingerprints. Existing public APIs and earlier ABI versions do
not change.

## Alternatives Rejected

- **Call `select/2` independently for every row:** this would reparse or require
  a raw cursor and multiply NIF crossings, plan compilation, and ownership
  transitions.
- **Materialize the target array in C++ or the BEAM:** memory would grow with
  total input records rather than one bounded batch.
- **Compile a projection per batch or row:** the immutable field topology is
  constant for the stream and must be reused.
- **Return a partial in-flight batch on error:** callers could not distinguish
  a complete committed native response from terms preceding a failed row.
- **Probe end with an extra request:** exact-boundary arrays would incur a
  needless native crossing and complicate call-count evidence.
- **Ignore content after the target array:** full successful enumeration could
  incorrectly accept malformed trailing document content.
- **Store an unretained parent pointer:** document close or garbage collection
  could free parser state still referenced by the cursor.

## Reopening Conditions

Revisit this decision if the pinned simdjson API cannot retain qualified nested
iterator state, if measured conversion costs justify a different batch
container, or if plan caching, resumable checkpoints, or parallel array
partitions are proposed. Any replacement must preserve forward-only ordering,
parent retention, bounded replies, plan reuse, transactional batches,
exception containment, and no per-row or per-field NIF calls.
