# Streaming API

Milestone 4 Phase 5 changes execution ownership only: the same lazy opaque
Enumerable submits setup and one batch at a time to the bounded native pool.
Pool controls and telemetry configuration remain private.

Current-truth contract for the Milestone 3 `SimdJson.stream/2` lazy
Enumerable, closed option grammar, projected row values, and indexed runtime
errors.

## Intent

This subject gives callers a composable way to process a very large target
array without constructing its complete BEAM list. It fixes construction
laziness, source and option validation, scalar row shape, ownership, exception
behavior, and public scope before a native cursor is implemented.

Phase 1 now implements this contract only behind an undocumented internal
preflight seam. It validates genuine source shape, the closed proper option
list, root or nested target paths, complete reused fields projections, exact
defaults and upper bounds, captures the constructing owner, and returns a
bounded redacted opaque term without JSON or native work. `SimdJson.Error` now
reserves `:batch_too_large` and optional checked `array_index`. `stream/2`,
`SimdJson.Stream`, Enumerable behavior, row delivery, and runtime stream errors
remain unimplemented, so this subject stays planned under its complete
bootstrap exception.

Phase 2 adds no public surface. It registers a private cursor resource and ABI
v3 ownership machinery that remain unreachable from `SimdJson`, so `stream/2`,
Enumerable reduction, row delivery, and runtime errors are still deferred.

Phase 3 likewise adds no public surface. Native row batches and indexed status
are exercised only by C and Zig qualification harnesses; `stream/2`, Enumerable
reduction, BEAM row conversion, and public runtime errors remain deferred.

Phase 4 adds no public surface. Its private reduction-start and batch-demand
seams prove lazy admission, exact copied row-map conversion, owner-first
document exclusion, one in-flight batch, no prefetch while idle, and terminal
cursor cleanup. `stream/2`, the opaque Enumerable implementation, public row
delivery, and stable runtime exception translation remain Phase 5 work.

Milestone 3 Phase 5 exposes `SimdJson.stream/2` and opaque `SimdJson.Stream.t()` with Enumerable and redacted Inspect implementations. Construction mistakes raise synchronously; native setup and batch failures raise stable redacted `SimdJson.Error` values during owner reduction.

Milestone 4 Phase 1 reserves the shared `:busy` reason for future immediate
global-capacity rejection. No Milestone 3 stream can produce it yet because the
bounded pool and queue do not exist; stream construction, demand, errors,
redaction, and Enumerable behavior otherwise remain unchanged.

```spec-meta
id: simd_json.streaming_api
kind: api
status: active
summary: Milestone 3 exposes one owner-bound lazy Enumerable that yields projected rows from bounded native batches.
surface:
  - lib/simd_json.ex
  - lib/simd_json/stream_options.ex
  - lib/simd_json/error.ex
  - test/**/*stream*
  - test/**/*enumerable*
  - docs/milestones/03-batched-array-streaming.md
decisions:
  - simd_json.lazy_stream_api_and_bounded_options
  - simd_json.forward_only_batched_array_cursor
  - simd_json.stream_ownership_backpressure_and_lifetime
  - simd_json.projection_api_and_validation
  - simd_json.document_resource_and_buffer_ownership
```

## Requirements

```spec-requirements
- id: simd_json.streaming_api.stream_contract
  statement: SimdJson.stream/2 shall accept a JSON binary or genuine SimdJson.Document plus validated stream options and return an opaque owner-bound SimdJson.Stream implementing Enumerable.
  priority: must
  stability: evolving

- id: simd_json.streaming_api.lazy_construction
  statement: Returning from SimdJson.stream/2 shall perform no JSON parse, document reservation, target lookup, native plan construction, cursor creation, threaded submission, or native allocation; those operations begin only when the owner reduces the Enumerable.
  priority: must
  stability: stable

- id: simd_json.streaming_api.source_argument_validation
  statement: SimdJson.stream/2 shall raise ArgumentError synchronously when source is neither a binary nor a genuine SimdJson.Document resource, before any native admission or document state change.
  priority: must
  stability: stable

- id: simd_json.streaming_api.option_grammar
  statement: Stream options shall be a proper keyword list containing required unique path and fields keys plus optional unique batch_size and max_batch_bytes keys, and every missing, duplicate, unknown, improper, or invalid option shall raise ArgumentError synchronously.
  priority: must
  stability: stable

- id: simd_json.streaming_api.target_path
  statement: The target path shall be a proper list of valid UTF-8 binary object segments and unsigned 64-bit array indexes, with an empty list selecting a top-level array and no JSONPath, wildcard, filter, recursive descent, or atom creation.
  priority: must
  stability: stable

- id: simd_json.streaming_api.fields_projection
  statement: The fields option shall use the complete non-empty Milestone 2 projection grammar, exact caller output-key identity, shared-path normalization, scalar-only leaves, first duplicate-key policy, and fresh copied strings relative to each array element.
  priority: must
  stability: stable

- id: simd_json.streaming_api.public_limits
  statement: batch_size shall default to 1000 and accept 1 through 10000, while max_batch_bytes shall default to 8388608 and accept 1 through 67108864; changing these values shall require renewed contract and qualification evidence.
  priority: must
  stability: stable

- id: simd_json.streaming_api.row_results
  statement: Reduction shall yield source-ordered maps using exact caller atom or binary keys and exact signed integer, unsigned integer, finite float, boolean, nil, or fresh binary values without retaining source, document, cursor, or native views.
  priority: must
  stability: stable

- id: simd_json.streaming_api.owner_bound_reduction
  statement: Only the PID that constructs a stream shall reduce it, possession shall not transfer ownership, binary streams may create a new independent cursor on a later owner reduction, and document streams shall remain one-shot after committed cursor access.
  priority: must
  stability: stable

- id: simd_json.streaming_api.runtime_exceptions
  statement: JSON, target, row projection, ownership, lifecycle, batch limit, allocation, cancellation, and native failures discovered during reduction shall raise SimdJson.Error only after current native cleanup completes, rather than yielding error tuples among row maps.
  priority: must
  stability: evolving

- id: simd_json.streaming_api.indexed_errors
  statement: SimdJson.Error shall support an optional non-negative array_index and shall report the zero-based source row index plus a validated caller field path for row-specific failures when known, without source text or unbounded native metadata.
  priority: must
  stability: evolving

- id: simd_json.streaming_api.transactional_batch_visibility
  statement: A failing in-flight native batch shall yield none of its rows, while rows from earlier completed batches remain observed and are not rolled back.
  priority: must
  stability: stable

- id: simd_json.streaming_api.opaque_stream
  statement: SimdJson.Stream shall expose an opaque type and bounded redacted inspection that reveals no source bytes, output keys, paths, owner PID, document identity, cursor state, generation, native pointer, or request reference.
  priority: must
  stability: stable

- id: simd_json.streaming_api.milestone_scope
  statement: Milestone 3 shall expose no public stream_batches operation, raw cursor, manual next, rewind, checkpoint, resume, transfer, prefetch, parallel array traversal, native callback, optional field, container result, compiled plan, JSONPath, eager decode, worker-pool control, diagnostic, or telemetry API.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.streaming_api.lazy_binary_stream
  covers:
    - simd_json.streaming_api.stream_contract
    - simd_json.streaming_api.lazy_construction
    - simd_json.streaming_api.row_results
  given:
    - A valid large JSON binary containing a target array
    - Valid target, fields, and batch options
  when:
    - The stream is constructed, observed without reduction, and then fully reduced by its owner
  then:
    - Construction creates no request, parser, document, plan, cursor, or batch
    - Reduction yields projected row maps in source order
    - Completed rows remain valid after all native state is released

- id: simd_json.streaming_api.root_and_nested_arrays
  covers:
    - simd_json.streaming_api.target_path
    - simd_json.streaming_api.fields_projection
    - simd_json.streaming_api.row_results
  given:
    - Top-level and nested arrays containing objects with shared, identical, object, and array field paths
  when:
    - Streams use an empty root path and mixed valid nested paths
  then:
    - Each target is located once and rows preserve array order
    - Exact caller keys and every supported scalar type are returned
    - Unselected containers never become BEAM terms

- id: simd_json.streaming_api.invalid_construction
  covers:
    - simd_json.streaming_api.source_argument_validation
    - simd_json.streaming_api.option_grammar
    - simd_json.streaming_api.target_path
    - simd_json.streaming_api.fields_projection
    - simd_json.streaming_api.public_limits
  given:
    - Forged or invalid sources and every missing, duplicate, unknown, improper, malformed, or out-of-range option family
  when:
    - SimdJson.stream/2 is called
  then:
    - ArgumentError is raised synchronously
    - No source byte is inspected and no document or native state changes

- id: simd_json.streaming_api.batch_boundaries
  covers:
    - simd_json.streaming_api.public_limits
    - simd_json.streaming_api.row_results
  given:
    - Empty arrays and arrays smaller than, equal to, and larger than one configured batch
    - A byte limit that causes a batch to stop before its row-count limit
  when:
    - Each stream is fully enumerated
  then:
    - Every source row appears exactly once and in order
    - Empty arrays yield no rows
    - Exact-boundary completion causes no duplicate, omission, or public empty sentinel

- id: simd_json.streaming_api.midstream_failure
  covers:
    - simd_json.streaming_api.runtime_exceptions
    - simd_json.streaming_api.indexed_errors
    - simd_json.streaming_api.transactional_batch_visibility
  given:
    - Several successful batches followed by a missing field, wrong type, oversized row, numeric range failure, or malformed source
  when:
    - Reduction reaches the failing row
  then:
    - SimdJson.Error is raised with stable reason, zero-based array index, and validated field path when available
    - No row from the failing batch is yielded
    - Earlier completed rows remain already observed and cursor cleanup finishes before the exception escapes

- id: simd_json.streaming_api.owner_and_reduction_semantics
  covers:
    - simd_json.streaming_api.owner_bound_reduction
    - simd_json.streaming_api.runtime_exceptions
  given:
    - Binary-backed and document-backed streams constructed by process A and sent to process B
  when:
    - Process B reduces them and process A later performs valid and repeated reductions
  then:
    - Process B receives not_owner without cursor or document mutation
    - Process A may re-reduce a binary stream through a new independent cursor
    - A committed document stream is consumed and cannot be transparently replayed

- id: simd_json.streaming_api.early_halt_and_consumer_exception
  covers:
    - simd_json.streaming_api.runtime_exceptions
    - simd_json.streaming_api.row_results
  given:
    - A target array much larger than one batch
  when:
    - Enum.take, Enum.find, reducer halt, and a consumer callback exception stop reduction early
  then:
    - Only demanded rows are observed
    - Remaining source rows are not parsed for stream completion
    - Native cleanup completes and successful copied rows remain independent

- id: simd_json.streaming_api.surface_and_redaction
  covers:
    - simd_json.streaming_api.opaque_stream
    - simd_json.streaming_api.milestone_scope
    - simd_json.streaming_api.indexed_errors
  given:
    - Stream terms, runtime errors, public modules, documentation, exports, typespecs, and protocols
  when:
    - They are inspected and enumerated
  then:
    - Source, paths, keys, owner and native identity remain redacted
    - Only stream/2 and the opaque Enumerable type are added for Milestone 3
    - Every deferred streaming, cursor, decode, concurrency, and diagnostic surface remains absent
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed constructor,
option grammar, laziness, typespec, doctest, Enumerable, scalar row, boundary,
ownership, replay, indexed-error, batch atomicity, early-halt, redaction, atom
safety, and public-surface evidence through the real native stream path.

## Verification

```spec-verification
- kind: command
  target: MIX_ENV=test mix test test/simd_json/stream_options_test.exs test/simd_json/stream_constructor_test.exs test/simd_json/stream_enumerable_test.exs test/simd_json/phase_5_integration_test.exs
  execute: true
  covers:
    - simd_json.streaming_api.stream_contract
    - simd_json.streaming_api.lazy_construction
    - simd_json.streaming_api.source_argument_validation
    - simd_json.streaming_api.option_grammar
    - simd_json.streaming_api.target_path
    - simd_json.streaming_api.fields_projection
    - simd_json.streaming_api.public_limits
    - simd_json.streaming_api.row_results
    - simd_json.streaming_api.owner_bound_reduction
    - simd_json.streaming_api.runtime_exceptions
    - simd_json.streaming_api.indexed_errors
    - simd_json.streaming_api.transactional_batch_visibility
    - simd_json.streaming_api.opaque_stream
    - simd_json.streaming_api.milestone_scope
    - simd_json.streaming_api.lazy_binary_stream
    - simd_json.streaming_api.root_and_nested_arrays
    - simd_json.streaming_api.invalid_construction
    - simd_json.streaming_api.batch_boundaries
    - simd_json.streaming_api.midstream_failure
    - simd_json.streaming_api.owner_and_reduction_semantics
    - simd_json.streaming_api.early_halt_and_consumer_exception
    - simd_json.streaming_api.surface_and_redaction
```
