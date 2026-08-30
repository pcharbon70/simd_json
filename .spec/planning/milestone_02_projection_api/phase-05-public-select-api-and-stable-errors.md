# Phase 5 — Public Select API and Stable Errors

Back to plan: [README](./README.md)

- [x] 5 Phase - Expose the qualified internal projection slice as
  `SimdJson.select/2` with exact results, stable path errors, and a locked
  Milestone 2 public surface.

  This phase adds binary and document dispatch to the root module, routes both
  forms through Phase 1 preflight and Phase 4 threaded execution, translates
  every native outcome once, and documents one-shot document behavior. It also
  reconciles Milestone 1 scope assertions that intentionally prohibited
  projection before this milestone. Qualification and spec activation remain
  Phase 6 responsibilities.

  Contract focus:

  - `simd_json.projection_api.select_contract`
  - `simd_json.projection_api.source_argument_validation`
  - `simd_json.projection_api.output_key_identity`
  - `simd_json.projection_api.scalar_results`
  - `simd_json.projection_api.fresh_string_results`
  - `simd_json.projection_api.atomic_result`
  - `simd_json.projection_api.projection_error_reasons`
  - `simd_json.projection_api.error_path`
  - `simd_json.projection_api.milestone_scope`
  - `simd_json.projection_api.binary_multi_select`
  - `simd_json.projection_api.document_select`
  - `simd_json.projection_api.invalid_source_argument`
  - `simd_json.projection_api.all_scalar_types`
  - `simd_json.projection_api.path_failures`
  - `simd_json.projection_api.atom_and_surface_safety`
  - `simd_json.projection_execution.binary_operation_lifetime`
  - `simd_json.projection_execution.document_one_shot`
  - `simd_json.projection_execution.submission_rejection_retry`

## 5.1 Section — Public Function and Source Dispatch

- [x] 5.1 Section - Add one typed public function that validates caller terms
  and dispatches binary or genuine document sources to the same native engine.

  This section preserves the existing argument-versus-operational error
  boundary and exposes no intermediate plan, document, cursor, slot, request,
  or native resource.

  - [x] 5.1.1 Task - Define `SimdJson.select/2` and public types.

    The task makes the API discoverable and Dialyzer-friendly while keeping the
    projection grammar closed and result shape transactional.

    - [x] 5.1.1.1 Subtask - Add public types for output key, object/index path segment, non-empty path, projection entry, projection, scalar result, and projection result map without publishing the normalized internal struct.
    - [x] 5.1.1.2 Subtask - Add `select(binary() | SimdJson.Document.t(), projection()) :: {:ok, map()} | {:error, SimdJson.Error.t()}` to the root module.
    - [x] 5.1.1.3 Subtask - Document tagged operational failure, `ArgumentError` source misuse, strict projection failure, one-shot document semantics, fresh string ownership, and scalar-only leaves.
    - [x] 5.1.1.4 Subtask - Add no bang variant, default-field options, map grammar, compiled-plan overload, or source-reparse option.

  - [x] 5.1.2 Task - Implement source discrimination and validation order.

    The task guarantees all source and projection checks happen at their
    accepted boundary before private threaded admission.

    - [x] 5.1.2.1 Subtask - Accept binaries directly and accept document values only after decoding a genuine registered resource rather than trusting struct shape.
    - [x] 5.1.2.2 Subtask - Raise `ArgumentError` for every other source value before a request reference, resource reservation, or native allocation exists.
    - [x] 5.1.2.3 Subtask - Run complete projection preflight before binary parsing or document reservation and return its stable invalid-projection error unchanged.
    - [x] 5.1.2.4 Subtask - Route accepted binary and document requests into the same private projection operation and return only its correlated terminal tagged result.

## 5.2 Section — Result Construction and Error Translation

- [x] 5.2 Section - Present native scalar slots and statuses through one exact,
  redacted Elixir contract.

  This section prevents native enum, slot, cursor, string-view, and partial-term
  details from becoming public behavior.

  - [x] 5.2.1 Task - Complete exact result-map conversion.

    The task proves each native scalar and caller output key reaches the public
    map without source retention or unwanted coercion.

    - [x] 5.2.1.1 Subtask - Construct exact signed and unsigned BEAM integers, finite floats, booleans, nil, and fresh binaries for the full scalar corpus.
    - [x] 5.2.1.2 Subtask - Use the exact supplied atom or binary key for every output slot and allow identical paths with distinct keys to receive independent result entries.
    - [x] 5.2.1.3 Subtask - Return the map only after every key/value pair has been constructed successfully in the private environment and transferred as one terminal result.
    - [x] 5.2.1.4 Subtask - Prove selected strings and the result map remain valid after binary temporary cleanup or explicit document close and do not retain a large source allocation.

  - [x] 5.2.2 Task - Translate projection statuses and failing paths once.

    The task extends the existing private translator instead of letting C++, Zig,
    coordinator, and Elixir wrappers invent different errors.

    - [x] 5.2.2.1 Subtask - Map every ABI v2 status to the closed `SimdJson.Error.reason` set and unknown codes to `native_failure` with numeric diagnostics only.
    - [x] 5.2.2.2 Subtask - Resolve an available failing slot to its copied caller path and validate that metadata against the normalized projection before returning it.
    - [x] 5.2.2.3 Subtask - Preserve logical byte offsets for parse failures, set unavailable offsets and paths to `nil`, and never derive either field from padding or a source substring.
    - [x] 5.2.2.4 Subtask - Use controlled messages and redacted inspection/logging for missing, index, type, range, consumed, cancelled, allocation, submission, and internal errors.

  - [x] 5.2.3 Task - Enforce all-or-nothing public failure.

    The task proves early successful paths and converted terms cannot leak when
    anything later fails.

    - [x] 5.2.3.1 Subtask - Exercise a failure after each filled native slot and each constructed BEAM key/value and assert no partial map is delivered.
    - [x] 5.2.3.2 Subtask - Treat requested object and array terminals as `incorrect_type` without serializing, copying, inspecting, or retaining their contents.
    - [x] 5.2.3.3 Subtask - Confirm malformed unselected and trailing input returns a parse error even when all requested scalar slots were already located.

## 5.3 Section — Documentation and Milestone Scope Reconciliation

- [x] 5.3 Section - Make public documentation, active Milestone 1 contracts, and
  export allowlists describe the newly expanded but still narrow package.

  This section changes current truth deliberately: projection becomes public,
  while streaming, eager decode, raw cursors, compiled plans, and production
  concurrency remain absent.

  - [x] 5.3.1 Task - Publish projection API and lifecycle documentation.

    The task gives callers complete examples and limitations without requiring
    them to read native architecture research.

    - [x] 5.3.1.1 Subtask - Add README and module examples for atom and binary result keys, nested object/array paths, binary selection, document selection, stable path errors, consumption, and close.
    - [x] 5.3.1.2 Subtask - Add the Milestone 2 document to ExDoc extras and document scalar-only results, first-duplicate-key behavior, complete-source validation, fresh strings, and the pre-production runtime boundary.
    - [x] 5.3.1.3 Subtask - State explicitly that another projection requires another document or binary call and that no transparent rewind, reparse, or reusable compiled plan exists.

  - [x] 5.3.2 Task - Reconcile active package and Milestone 1 scope truth.

    The task removes only assertions whose current interpretation would forbid
    the accepted Milestone 2 API and preserves every foundation guarantee.

    - [x] 5.3.2.1 Subtask - Reframe `simd_json.document_api.milestone_scope` and `no_future_surface` so they preserve the Milestone 1 baseline while permitting the separately governed `select/2` addition.
    - [x] 5.3.2.2 Subtask - Update package and document API intent, summaries, surfaces, evidence inventories, and verification commands to describe projection without claiming Milestone 2 activation early.
    - [x] 5.3.2.3 Subtask - Add source and test coverage markers for new requirements without attaching a marker to behavior a file does not actually prove.
    - [x] 5.3.2.4 Subtask - Run `mix spec.next` immediately after reconciliation and resolve any reported subject or decision mismatch before proceeding.

  - [x] 5.3.3 Task - Lock the Milestone 2 public surface.

    The task protects the milestone boundary from convenient but unqualified
    additions.

    - [x] 5.3.3.1 Subtask - Update export, typespec, module, README, milestone, and protocol allowlists so `select/2` is the only new public root operation.
    - [x] 5.3.3.2 Subtask - Prove compiled plans, JSONPath, wildcard/filter/default policies, container materialization, streaming, cursors, transfer, raw handles, native diagnostics, and eager decode remain absent.
    - [x] 5.3.3.3 Subtask - Verify no public inspection or serialization path reveals normalized projections, native plan identity, cursor state, generation, timing, or source content.

## 5.4 Section — Phase 5 Integration Tests

- [x] 5.4 Section - Prove the complete public contract across grammar, scalar
  results, path failures, source forms, ownership, consumption, lifetime,
  redaction, and scope.

  This section closes user-visible behavior before Phase 6 records supported
  target, sanitizer, scheduler, memory, and benchmark evidence.

  - [x] 5.4.1 Task - Run the public functional and error corpora.

    The task executes every Projection API scenario through the real threaded
    native stack for binary and document sources.

    - [x] 5.4.1.1 Subtask - Select multiple shared and disjoint paths with atom/binary keys, object order opposite declaration order, array indexes, Unicode/escaped keys and strings, duplicate paths, and every scalar type.
    - [x] 5.4.1.2 Subtask - Test every invalid source and projection shape and prove `ArgumentError` versus `invalid_projection` plus zero native admission and non-consumption at the documented boundaries.
    - [x] 5.4.1.3 Subtask - Test missing fields, index bounds, wrong containers, container terminals, numeric range, malformed/UTF-8/truncated input, consumed documents, cancellation, submission rejection, allocation, and internal errors with stable redacted metadata.
    - [x] 5.4.1.4 Subtask - Inject late path and conversion failures after early success and assert no partial result, source-backed string, large retained binary, or leaked private environment.

  - [x] 5.4.2 Task - Run ownership, lifecycle, and public-surface gates.

    The task combines public terms, multiple BEAM processes, close/GC, doctests,
    and export inspection.

    - [x] 5.4.2.1 Subtask - Exercise fresh, selecting, consumed, closing, and closed documents from owner and non-owner processes and assert deterministic state plus idempotent owner close.
    - [x] 5.4.2.2 Subtask - Release successful and failing binary/document batches by return, close, caller death, and GC; await quiescence and require every bounded native gauge at baseline.
    - [x] 5.4.2.3 Subtask - Add doctests for binary/document success, invalid projection, path/type errors, one-shot consumption, fresh string lifetime, redacted inspection, and deferred features.
    - [x] 5.4.2.4 Subtask - Enumerate exports, typespecs, protocols, and documented functions against the Milestone 2 allowlist and prove no hidden bridge or future API escaped.
    - [x] 5.4.2.5 Subtask - Run focused public projection tests, API/resource/runtime qualification regressions, `mix test`, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 5 complete.
