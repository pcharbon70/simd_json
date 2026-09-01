# Phase 1 — Stream Contract and Preflight Options

Back to plan: [README](./README.md)

- [ ] 1 Phase - Implement the exact stream option grammar, normalized target
  and field representation, owner capture, and native-lazy preflight boundary.

  This phase turns ADR 0007 into executable caller-term validation. It reuses
  the Milestone 2 projection validator, defines stream-specific target and
  limit normalization, reserves indexed error metadata, and proves construction
  can inspect no JSON or native state. `SimdJson.stream/2` is not public yet;
  later phases consume the private normalized value.

  Contract focus:

  - `simd_json.streaming_api.source_argument_validation`
  - `simd_json.streaming_api.option_grammar`
  - `simd_json.streaming_api.target_path`
  - `simd_json.streaming_api.fields_projection`
  - `simd_json.streaming_api.public_limits`
  - `simd_json.streaming_api.indexed_errors`
  - `simd_json.streaming_api.lazy_construction`
  - `simd_json.stream_execution.lazy_setup`

## 1.1 Section — Stream Terms and Normalized Options

- [x] 1.1 Section - Define one private typed representation for source class,
  owner, target segments, row projection, and bounded batch limits.

  This section gives native phases a closed input model while preserving caller
  paths and keys for later row maps and errors. It publishes no Enumerable,
  cursor, native descriptor, or compiled plan.

  - [x] 1.1.1 Task - Define stream option and target types.

    The task models the closed keyword grammar and distinguishes root-array
    targeting from the non-empty per-row projection paths.

    - [x] 1.1.1.1 Subtask - Add a private `SimdJson.StreamOptions` module, or equivalent, with types for source class, owner PID, target segment, target path, normalized fields projection, batch size, and encoded-byte limit.
    - [x] 1.1.1.2 Subtask - Represent `path: []` as the root-array target while preserving every non-empty valid target path exactly for error translation.
    - [x] 1.1.1.3 Subtask - Embed or reference only a validator-produced Milestone 2 normalized projection; do not copy raw caller field terms into a second grammar implementation.
    - [x] 1.1.1.4 Subtask - Keep constructors private and expose no public stream, cursor, options struct, serialization, protocol, or native handle in this phase.

  - [x] 1.1.2 Task - Normalize limits and option identity deterministically.

    The task produces stable data Phase 2 can serialize without depending on
    keyword lookup behavior after duplicate information is lost.

    - [x] 1.1.2.1 Subtask - Record whether every accepted option was explicitly supplied before applying the exact defaults of 1000 rows and 8388608 encoded bytes.
    - [x] 1.1.2.2 Subtask - Normalize accepted limits only after validating positive integer and upper-bound domains, without truncating to a narrower native type.
    - [x] 1.1.2.3 Subtask - Preserve option order independence while rejecting duplicate keys and produce identical normalized output for equivalent valid keyword orderings.
    - [x] 1.1.2.4 Subtask - Capture `self()` as immutable owner metadata without exposing it through default inspection or diagnostic snapshots.

## 1.2 Section — Complete Preflight and Lazy Boundary

- [ ] 1.2 Section - Validate the source term and complete option list before
  any document reservation, request correlation, native submission, or JSON
  inspection.

  This section separates synchronous caller mistakes from failures that can
  occur only during Enumerable reduction. Validation may scale with options and
  projection size in yielding Elixir code; no ordinary NIF walks unbounded
  caller structures.

  - [ ] 1.2.1 Task - Validate source and option collection shape.

    The task accepts only the two source forms and four closed option keys while
    retaining enough information to reject every duplicate deterministically.

    - [ ] 1.2.1.1 Subtask - Accept a binary directly and accept a document only after a bounded genuine registered-resource check; raise `ArgumentError` for forged and every other source term.
    - [ ] 1.2.1.2 Subtask - Reject non-list, improper, non-keyword, empty, duplicate-key, unknown-key, and missing-required-key options with controlled `ArgumentError` messages.
    - [ ] 1.2.1.3 Subtask - Parse the proper option list once, without using a map conversion that would erase duplicates or enumerate source JSON data.
    - [ ] 1.2.1.4 Subtask - Prove source and option failures create no request reference, operation admission, allocation, generation change, or document reservation.

  - [ ] 1.2.2 Task - Validate target, fields, and numeric limits completely.

    The task checks every nested term before returning one normalized success
    value so malformed tails cannot reach native descriptor serialization.

    - [ ] 1.2.2.1 Subtask - Accept an empty target path and proper paths containing only valid UTF-8 binaries or integers in `0..18_446_744_073_709_551_615`; reject every other segment and improper tail.
    - [ ] 1.2.2.2 Subtask - Run `:fields` through the existing complete projection validator and preserve its exact key, segment, duplicate, scalar, UTF-8, and atom-safety rules.
    - [ ] 1.2.2.3 Subtask - Accept `batch_size` only in `1..10_000` and `max_batch_bytes` only in `1..67_108_864`, applying their decided defaults only when absent.
    - [ ] 1.2.2.4 Subtask - Walk late-invalid target, field, and option fixtures completely enough that no unchecked caller term reaches a later phase.

  - [ ] 1.2.3 Task - Make construction laziness observable.

    The task provides a private shell that later becomes public without
    accidentally starting a parse while merely building or inspecting it.

    - [ ] 1.2.3.1 Subtask - Return only a private normalized stream value or raise `ArgumentError`; do not call `SimdJson.open/1`, reserve a document, compile a plan, or create a cursor.
    - [ ] 1.2.3.2 Subtask - Add test-only admission and native-gauge snapshots proving valid and invalid construction produce zero setup, batch, parser, document, plan, and cursor deltas.
    - [ ] 1.2.3.3 Subtask - Exercise a genuine fresh document through the private seam and prove owner, lifecycle, generation, and one-shot cursor state remain unchanged until a later reduction start.

## 1.3 Section — Stream Error Metadata and Redaction

- [ ] 1.3 Section - Extend the common error contract for row-index and batch
  failures while preserving every Milestone 1 and 2 error behavior.

  This section gives later native statuses one translator target. It reserves
  types and safe metadata but does not synthesize runtime stream failures before
  the engine exists.

  - [ ] 1.3.1 Task - Add stream reasons and row index metadata.

    The task expands `SimdJson.Error` without changing existing reason, path,
    offset, native-code, message, or exception semantics.

    - [ ] 1.3.1.1 Subtask - Add `:batch_too_large` to the closed reason type while reusing existing parse, path, type, range, ownership, lifecycle, cancellation, allocation, and native reasons.
    - [ ] 1.3.1.2 Subtask - Add optional `array_index` metadata typed as a non-negative integer and default it to `nil` for every existing open, close, and select error.
    - [ ] 1.3.1.3 Subtask - Define controlled messages for oversized batches and indexed row failures while keeping reason, path, and array index as the only machine-readable fields.

  - [ ] 1.3.2 Task - Preserve error, option, and stream-shell redaction.

    The task ensures new context cannot expose source-derived content or
    unbounded caller data through default inspection.

    - [ ] 1.3.2.1 Subtask - Permit array index only from checked native status and path only from validated target or field options; never copy discovered JSON keys, values, or raw invalid terms.
    - [ ] 1.3.2.2 Subtask - Bound defensive inspection for forged reasons and numeric metadata and omit source, paths, output keys, owner PID, message text, native addresses, and C++ exceptions.
    - [ ] 1.3.2.3 Subtask - Re-run all active error, projection, and redaction doctests so existing errors retain `array_index: nil` and unchanged machine-readable meaning.

## 1.4 Section — Phase 1 Integration Tests

- [ ] 1.4 Section - Prove option grammar, deterministic normalization,
  construction laziness, atom safety, error extension, and unchanged public
  surface before ABI v3 work starts.

  This section freezes the only caller-term representation Phase 2 may consume
  and the negative fixtures every later public phase must preserve.

  - [ ] 1.4.1 Task - Run the complete option and normalization matrix.

    The task executes positive, negative, late-invalid, and generated cases
    through the real preflight implementation.

    - [ ] 1.4.1.1 Subtask - Accept root and mixed target paths, atom/binary field keys, shared/identical row paths, every scalar projection shape, defaults, and both numeric upper bounds.
    - [ ] 1.4.1.2 Subtask - Reject every invalid source, option collection, missing/unknown/duplicate key, target, field projection, improper list, UTF-8 value, index, and numeric-bound case.
    - [ ] 1.4.1.3 Subtask - Assert normalized output is deterministic across keyword ordering and preserves exact paths, fields, keys, limits, source class, and owner authority.

  - [ ] 1.4.2 Task - Run laziness, safety, and regression gates.

    The task proves preflight adds no hidden native work, atom growth, document
    consumption, error regression, or premature public feature.

    - [ ] 1.4.2.1 Subtask - Measure atom count across a large unique-binary target/field corpus and prove option validation creates no atoms from caller or JSON-like bytes.
    - [ ] 1.4.2.2 Subtask - Compare all admission, request, native allocation, lifecycle, generation, selection, and future stream gauges before and after valid and invalid private construction.
    - [ ] 1.4.2.3 Subtask - Enumerate public exports, typespecs, protocols, and docs and confirm `stream/2`, `SimdJson.Stream`, raw cursor, and batch APIs remain absent in this phase.
    - [ ] 1.4.2.4 Subtask - Run focused option/error tests, every Milestone 1 and 2 regression suite, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 1 complete.
