# Phase 1 — Projection Contract and Preflight Validation

Back to plan: [README](./README.md)

- [x] 1 Phase - Implement the exact Elixir projection grammar and a complete,
  non-consuming preflight boundary before any projection-native behavior is
  reachable.

  This phase turns ADR 0004 into executable term validation. It introduces an
  internal normalized projection representation, extends the structured error
  type for future projection failures, and proves invalid caller terms cannot
  submit native work, consume a document, or create atoms. `SimdJson.select/2`
  is not public yet; later phases consume the validator through a private seam.

  Contract focus:

  - `simd_json.projection_api.projection_grammar`
  - `simd_json.projection_api.complete_preflight_validation`
  - `simd_json.projection_api.output_key_identity`
  - `simd_json.projection_api.projection_error_reasons`
  - `simd_json.projection_api.error_path`
  - `simd_json.projection_api.invalid_projection`
  - `simd_json.projection_execution.preadmission_nonconsumption`

## 1.1 Section — Projection Terms and Normalized Representation

- [x] 1.1 Section - Define one typed internal representation for validated
  output keys, paths, segments, and output slots.

  This section gives later native phases a closed input model. Raw caller terms
  never flow directly into C++ traversal, and the representation records caller
  identity without encoding traversal order.

  - [x] 1.1.1 Task - Define projection and path types.

    The task models the accepted list-of-pairs grammar without exposing a
    compiled plan or native handle publicly.

    - [x] 1.1.1.1 Subtask - Add a private `SimdJson.Projection` module, or equivalent internal module, with types for atom-or-binary output keys, UTF-8 binary object segments, unsigned 64-bit array segments, normalized entries, and stable output-slot indexes.
    - [x] 1.1.1.2 Subtask - Represent paths as non-empty proper sequences and preserve the exact caller-supplied path for error reporting separately from any native byte arena or reordered traversal data.
    - [x] 1.1.1.3 Subtask - Allow multiple output slots to reference one identical normalized path while keeping output keys unique.
    - [x] 1.1.1.4 Subtask - Keep all representation constructors private and expose no public compiled-projection struct, protocol, serialization, or resource.

  - [x] 1.1.2 Task - Define deterministic normalized output.

    The task produces a stable representation that Phase 2 can serialize into
    ABI descriptors without depending on map enumeration or keyword semantics.

    - [x] 1.1.2.1 Subtask - Assign output slots by caller declaration position while preserving exact atom or binary output keys for final map construction.
    - [x] 1.1.2.2 Subtask - Normalize array indexes into the private unsigned 64-bit domain without truncation and retain object-key bytes exactly after UTF-8 validation.
    - [x] 1.1.2.3 Subtask - Make normalization deterministic for identical input terms and test that map ordering, VM hash seed, and JSON source order cannot affect its output.

## 1.2 Section — Complete Preflight Validator

- [x] 1.2 Section - Validate the entire projection in Elixir before resource
  reservation, request correlation, or native submission.

  This section separates caller grammar failures from parser and lifecycle
  failures. Validation may scale with caller projection size through normal
  reduction-yielding Elixir code, but no ordinary NIF performs an unbounded
  walk of the term.

  - [x] 1.2.1 Task - Validate the outer collection and output keys.

    The task accepts exactly the ADR's non-empty proper list and detects
    duplicates before information can be lost in a result map.

    - [x] 1.2.1.1 Subtask - Reject empty lists, maps, tuples that are not two-tuples, improper lists, and non-list collections with `:invalid_projection`.
    - [x] 1.2.1.2 Subtask - Accept only existing atom and binary output keys and preserve their exact term identity without string conversion or atom creation.
    - [x] 1.2.1.3 Subtask - Detect duplicate output keys across the complete list using exact BEAM key equality before producing normalized output.
    - [x] 1.2.1.4 Subtask - Verify the validator never calls atom-creation functions and that arbitrarily many unique binary keys do not grow the atom table.

  - [x] 1.2.2 Task - Validate every path and segment.

    The task exhaustively checks path shape and segment domains before returning
    the first deterministic validation error.

    - [x] 1.2.2.1 Subtask - Reject empty and improper paths while accepting an empty binary as a valid object-key segment.
    - [x] 1.2.2.2 Subtask - Require every binary segment to contain valid UTF-8 without unescaping or interpreting it as JSON source text.
    - [x] 1.2.2.3 Subtask - Accept integer segments only in `0..18_446_744_073_709_551_615` and reject negative, oversized, float, atom, tuple, map, and nested-list segments.
    - [x] 1.2.2.4 Subtask - Walk the complete projection even when fixtures place malformed terms late, proving no unchecked tail reaches native serialization.

  - [x] 1.2.3 Task - Preserve the non-consuming boundary.

    The task makes preflight an independently observable step that later source
    dispatch can call before touching document state or JSON bytes.

    - [x] 1.2.3.1 Subtask - Return one internal success value or `{:error, %SimdJson.Error{reason: :invalid_projection}}` without creating a request reference.
    - [x] 1.2.3.2 Subtask - Add test-only admission counters proving invalid projections invoke no Zigler or native entrypoint.
    - [x] 1.2.3.3 Subtask - Exercise validation with a genuine fresh document through a private test seam and prove lifecycle, generation, and future selection state remain unchanged.

## 1.3 Section — Projection Error Vocabulary and Redaction

- [x] 1.3 Section - Extend the common error type with the closed Milestone 2
  vocabulary while preserving existing Milestone 1 behavior.

  This section makes later layers share one translator target. It adds types and
  safe fields now, but does not expose selection or synthesize runtime errors
  that have no implementation yet.

  - [x] 1.3.1 Task - Add projection reasons and caller-path metadata.

    The task expands `SimdJson.Error` without changing the meaning of existing
    parse, ownership, lifecycle, allocation, and native reasons.

    - [x] 1.3.1.1 Subtask - Add `:invalid_projection`, `:no_such_field`, `:index_out_of_bounds`, `:incorrect_type`, `:number_out_of_range`, `:cursor_consumed`, and `:cancelled` to the closed reason type.
    - [x] 1.3.1.2 Subtask - Add optional `path` metadata typed as the accepted caller path and default it to `nil` for all existing errors.
    - [x] 1.3.1.3 Subtask - Construct invalid-projection messages from controlled templates and treat reason, not message, as the machine-readable field.

  - [x] 1.3.2 Task - Preserve error and inspection redaction.

    The task ensures adding path context does not admit source excerpts or
    native diagnostics into default output.

    - [x] 1.3.2.1 Subtask - Permit `path` to contain only a copy of a caller-supplied validated path; invalid raw terms and discovered JSON text never become path metadata.
    - [x] 1.3.2.2 Subtask - Update `Inspect` so it remains bounded and contains no error message, source substring, owner PID, native address, or C++ exception text.
    - [x] 1.3.2.3 Subtask - Re-run all Milestone 1 error doctests and redaction tests to prove their exact reason and default field behavior remain compatible.

## 1.4 Section — Phase 1 Integration Tests

- [x] 1.4 Section - Prove the grammar, normalization, atom boundary, error
  extension, and non-consuming behavior before native plan work starts.

  This section closes the only caller-term boundary Phase 2 is allowed to
  consume and freezes fixtures shared by every later phase.

  - [x] 1.4.1 Task - Run the complete projection grammar matrix.

    The task executes positive and negative table-driven cases plus generated
    combinations through the real validator.

    - [x] 1.4.1.1 Subtask - Accept keyword-style atom keys, binary keys, empty object keys, Unicode paths, zero and `UINT64_MAX` indexes, shared prefixes, and identical paths with distinct output keys.
    - [x] 1.4.1.2 Subtask - Reject every invalid outer shape, key, duplicate key, path, UTF-8 binary, index, segment, and improper-list case with the stable reason.
    - [x] 1.4.1.3 Subtask - Assert normalized output is deterministic and preserves exact output keys, paths, slot positions, and index values.

  - [x] 1.4.2 Task - Run safety and regression integration gates.

    The task proves validation adds no hidden native work or atom/lifecycle
    regression and leaves the public surface unchanged.

    - [x] 1.4.2.1 Subtask - Measure atom count before and after validating a large unique-binary-key corpus and prove it does not grow because of projection data.
    - [x] 1.4.2.2 Subtask - Assert invalid projection validation creates no native request, allocation, lifecycle transition, generation change, or document consumption.
    - [x] 1.4.2.3 Subtask - Enumerate public exports and confirm `select/2` and compiled-plan functions remain absent in this phase.
    - [x] 1.4.2.4 Subtask - Run focused projection/error tests, the full Milestone 1 test suite, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 1 complete.
