# Phase 5 — Public Enumerable and Stable Errors

Back to plan: [README](./README.md)

- [ ] 5 Phase - Expose the qualified internal stream slice as lazy
  `SimdJson.stream/2`, flatten bounded batches into exact row maps, raise stable
  indexed runtime errors, and lock the Milestone 3 public surface.

  This phase adds the opaque stream type and Enumerable implementation, routes
  reduction through Phase 4 setup/batches, runs deterministic cleanup for every
  reducer outcome, and documents source ownership and bounds. It reconciles
  earlier scope assertions that intentionally prohibited streaming.
  Qualification and spec activation remain Phase 6 work.

  Contract focus:

  - every requirement and scenario in `simd_json.streaming_api`
  - `simd_json.stream_cursor.copied_row_values`
  - `simd_json.stream_cursor.batch_boundary`
  - `simd_json.stream_execution.lazy_setup`
  - `simd_json.stream_execution.owner_first_admission`
  - `simd_json.stream_execution.single_in_flight_batch`
  - `simd_json.stream_execution.no_prefetch`
  - `simd_json.stream_execution.early_halt_cleanup`
  - `simd_json.stream_execution.document_one_shot_and_close`
  - `simd_json.stream_execution.slow_consumer_backpressure`
  - `simd_json.stream_execution.early_halt_and_consumer_death`

## 5.1 Section — Public Stream Function and Opaque Type

- [ ] 5.1 Section - Add one typed public constructor whose result performs no
  native work until its owner begins Enumerable reduction.

  This section preserves the caller-mistake versus runtime-error boundary and
  exposes no intermediate document, plan, cursor, batch, request, or native
  resource.

  - [ ] 5.1.1 Task - Define `SimdJson.stream/2` and public types.

    The task makes the API discoverable and Dialyzer-friendly while keeping
    options, rows, ownership, and limits exact.

    - [ ] 5.1.1.1 Subtask - Add public types for target segment/path, fields projection, stream options, row scalar/map, and opaque `SimdJson.Stream.t()` without publishing normalized or native structs.
    - [ ] 5.1.1.2 Subtask - Add `stream(binary() | SimdJson.Document.t(), keyword()) :: SimdJson.Stream.t()` to the root module and capture the constructing PID.
    - [ ] 5.1.1.3 Subtask - Document immediate `ArgumentError`, lazy `SimdJson.Error`, binary replay, document one-shot behavior, exact limits/defaults, copied strings, scalar-only rows, and per-stream demand.
    - [ ] 5.1.1.4 Subtask - Add no bang, tagged-item, batch, cursor, next, rewind, transfer, prefetch, default-field, compiled-plan, or callback variant.

  - [ ] 5.1.2 Task - Preserve construction validation and opacity.

    The task routes only validated private state into the public shell and keeps
    construction observationally native-lazy.

    - [ ] 5.1.2.1 Subtask - Accept binaries and genuine document resources, raise for every invalid source/option term, and reuse Phase 1 normalization without duplicate validation logic.
    - [ ] 5.1.2.2 Subtask - Store source and normalized state behind an opaque representation whose public fields, protocols, serialization, and accessors cannot reveal internals.
    - [ ] 5.1.2.3 Subtask - Implement bounded redacted `Inspect` showing at most safe static configuration and source class, never source, keys, paths, owner, document, request, or cursor identity.
    - [ ] 5.1.2.4 Subtask - Prove construction, copy, inspection, pattern attempts, and garbage collection before reduction create no request, native graph, document use, or cleanup operation.

## 5.2 Section — Enumerable Reduction, Row Delivery, and Errors

- [ ] 5.2 Section - Turn private bounded batches into a row-by-row Enumerable
  with one setup, demand-driven next calls, and deterministic after cleanup.

  This section makes ordinary Enum and Stream composition safe without exposing
  native batch sentinels or mixing maps with error tuples.

  - [ ] 5.2.1 Task - Implement the Enumerable lifecycle.

    The task maps protocol start, next, halt, suspend, resume, and after behavior
    to the accepted private cursor operations.

    - [ ] 5.2.1.1 Subtask - On first reduction, verify constructing owner and run exactly one lazy setup operation; raise its translated error only after setup cleanup is complete.
    - [ ] 5.2.1.2 Subtask - Request one native batch when no returned rows remain, retain its list in Enumerable state, and yield maps in source order before another request.
    - [ ] 5.2.1.3 Subtask - Consume explicit native done metadata without yielding an empty batch or sentinel and support empty, partial-final, and full-final arrays without an extra request.
    - [ ] 5.2.1.4 Subtask - Handle Enumerable suspension and resume without cursor advancement while suspended and preserve exact current-list position and batch sequence.

  - [ ] 5.2.2 Task - Finalize every reducer path deterministically.

    The task ensures natural completion and all early exits close exactly once
    before returning control or propagating an exception.

    - [ ] 5.2.2.1 Subtask - On natural done, close cursor after final validation and release binary/document stream-owned state before reduction returns.
    - [ ] 5.2.2.2 Subtask - On reducer halt, `Enum.take`, `Enum.find`, suspension abandonment, or consumer callback exception, cancel if necessary and close without scanning the remaining array.
    - [ ] 5.2.2.3 Subtask - Preserve the consumer's original exception and stacktrace after stream cleanup and never replace it with a successful halt or secondary cleanup message.
    - [ ] 5.2.2.4 Subtask - Keep the resource destructor as an idempotent fallback for abandoned protocol state rather than a second normal finalization path.

  - [ ] 5.2.3 Task - Translate runtime errors with row context.

    The task maps one native status vocabulary into the public exception without
    exposing cursor, slot, source, or partial batch details.

    - [ ] 5.2.3.1 Subtask - Map target, row, parse, ownership, lifecycle, size, allocation, cancellation, submission, and unknown native statuses to the closed `SimdJson.Error.reason` set.
    - [ ] 5.2.3.2 Subtask - Validate native row index and failing slot, resolve the slot only through normalized fields, and attach copied caller path plus zero-based `array_index` when appropriate.
    - [ ] 5.2.3.3 Subtask - Preserve logical offsets and bounded numeric native codes, set unavailable index/path/offset to nil, and use only controlled message templates.
    - [ ] 5.2.3.4 Subtask - Raise only after the current failed batch, private environment, cursor, and source graph have reached their required terminal cleanup state.

  - [ ] 5.2.4 Task - Enforce row and batch visibility.

    The task proves the public consumer receives exact independent rows but no
    partial current batch after a later row failure.

    - [ ] 5.2.4.1 Subtask - Yield exact-key scalar maps with fresh binaries and prove no row retains input, parent document, cursor, batch arena, or private environment.
    - [ ] 5.2.4.2 Subtask - Inject failure after each native row and each BEAM map/list conversion step and assert no map from the failing batch reaches the reducer.
    - [ ] 5.2.4.3 Subtask - Verify rows delivered by earlier batches remain ordinary values after a later exception and are neither mutated nor rolled back.

## 5.3 Section — Documentation and Current-Truth Reconciliation

- [ ] 5.3 Section - Make public docs, active earlier contracts, package truth,
  and allowlists describe the added Enumerable without claiming qualification
  or production concurrency early.

  This section permits exactly the accepted streaming addition while preserving
  all open, close, select, ABI, ownership, projection, and error guarantees.

  - [ ] 5.3.1 Task - Publish stream API and lifecycle documentation.

    The task gives callers complete usage and failure guidance without requiring
    native architecture research.

    - [ ] 5.3.1.1 Subtask - Add README, module, and milestone examples for root/nested arrays, exact options/defaults, row projections, Stream/Enum composition, empty/exact batches, runtime rescue, early halt, and document streaming.
    - [ ] 5.3.1.2 Subtask - Document construction laziness, owner capture, binary replay, document consumption, first duplicate key, scalar-only rows, copied strings, whole-failing-batch behavior, full completion validation, and early-halt non-validation.
    - [ ] 5.3.1.3 Subtask - Explain row and byte bounds, one returned/in-flight batch, no prefetch, retained input, pre-production runtime limits, and safe batch-size tuning without universal performance claims.
    - [ ] 5.3.1.4 Subtask - Add the Milestone 3 guide to ExDoc extras while keeping raw operations, test diagnostics, failure seams, native counters, and acceptance internals undocumented.

  - [ ] 5.3.2 Task - Reconcile active earlier scope truth.

    The task removes only assertions whose current interpretation would forbid
    the accepted stream and updates affected subjects without rewriting their
    milestone history.

    - [ ] 5.3.2.1 Subtask - Reframe document and projection API scope scenarios so separately governed `stream/2` is allowed while raw cursors, ungoverned variants, eager decode, transfer, and production controls remain absent.
    - [ ] 5.3.2.2 Subtask - Update package, document-resource, native-execution, projection, README, native guide, surfaces, evidence inventories, and qualification commands where actual streaming implementation changes current truth.
    - [ ] 5.3.2.3 Subtask - Add accurate `covers:` markers and test targets for inherited parent retention, projection reuse, scheduler, lifecycle, error, and package claims without crediting policy-only files as behavior.
    - [ ] 5.3.2.4 Subtask - Run `mix spec.next` immediately after reconciliation and resolve every subject or decision mismatch before proceeding.

  - [ ] 5.3.3 Task - Lock the Milestone 3 public surface.

    The task protects the narrow API from convenient but unqualified additions.

    - [ ] 5.3.3.1 Subtask - Update export, typespec, module, README, milestone, Inspect, Enumerable, protocol, and ExDoc allowlists so only `stream/2` and the opaque stream type are added.
    - [ ] 5.3.3.2 Subtask - Prove stream_batches, raw cursor/next, rewind, checkpoint/resume, transfer, prefetch, parallel traversal, native callbacks, optional fields, container results, compiled plans, JSONPath, eager decode, pool controls, and telemetry remain absent.
    - [ ] 5.3.3.3 Subtask - Verify no inspection, protocol, serialization, exception, log, or documentation path reveals normalized options, source, owner, document/cursor identity, generation, request, timing, or native diagnostics.

## 5.4 Section — Phase 5 Integration Tests

- [ ] 5.4 Section - Prove the complete public contract across laziness,
  options, Enumerable control flow, row results, batch boundaries, indexed
  failures, ownership, backpressure, cleanup, redaction, and scope.

  This section closes user-visible behavior before Phase 6 records supported
  target, sanitizer, scheduler, memory, and ETL evidence.

  - [ ] 5.4.1 Task - Run public functional and error corpora.

    The task executes every Streaming API scenario through the real threaded
    native stack for binary and document sources.

    - [ ] 5.4.1.1 Subtask - Stream root/nested empty, small, exact-boundary, multi-batch, byte-limited, Unicode, duplicate-key, shared/identical-field, and all-scalar fixtures with exact source order and key identity.
    - [ ] 5.4.1.2 Subtask - Test every invalid source and option shape and prove synchronous `ArgumentError`, zero native work, unchanged document state, deterministic defaults, and atom safety.
    - [ ] 5.4.1.3 Subtask - Test target and row missing/index/type/range/UTF-8/EOF/invalid/oversized/cancelled/allocation/submission/internal failures with stable reason, index, path, offset, and redaction.
    - [ ] 5.4.1.4 Subtask - Inject late row and conversion failures after early native success and prior delivered batches; assert no current-batch row, source-backed string, retained batch, or leaked environment.

  - [ ] 5.4.2 Task - Run Enumerable, ownership, lifecycle, and surface gates.

    The task combines real protocols, multiple processes, pauses, early exits,
    document states, GC, doctests, and export inspection.

    - [ ] 5.4.2.1 Subtask - Exercise `Enum.to_list`, reduce, take, find, halt, suspend/resume, consumer raise, and consumer death; require exact demand, no extra done request, deterministic cleanup, and preserved exception semantics.
    - [ ] 5.4.2.2 Subtask - Exercise binary replay and owner/non-owner document streams across fresh/selecting/streaming/consumed/closing/closed states, including select races and idempotent owner close.
    - [ ] 5.4.2.3 Subtask - Pause consumers across thousands of batches and require one active/returned batch, no prefetch or mailbox growth, bounded peak state, then exact baseline recovery by done, halt, error, close, and GC.
    - [ ] 5.4.2.4 Subtask - Add doctests for construction laziness, root/nested success, invalid options, runtime indexed error, early halt, document consumption, redacted inspection, and deferred features.
    - [ ] 5.4.2.5 Subtask - Enumerate exports, typespecs, protocols, docs, symbols, and strings against the Milestone 3 allowlist and prove no internal or future API escaped.
    - [ ] 5.4.2.6 Subtask - Run focused public streaming, API/resource/projection/runtime regressions, `mix test`, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 5 complete.
