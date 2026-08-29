# Phase 4 — Threaded Projection and Document Consumption

Back to plan: [README](./README.md)

- [ ] 4 Phase - Connect projection to the correlated threaded runtime, implement
  one-shot document state, and make binary and document result lifetimes safe.

  This phase makes the native engine reachable only through private integration
  seams. It adds a projection operation kind, retains every resource through
  conversion and delivery, introduces `fresh -> selecting -> consumed`, builds
  complete BEAM results off scheduler, and owns the binary form's temporary
  document entirely inside one operation. The public root API remains deferred
  to Phase 5.

  Contract focus:

  - `simd_json.projection_engine.transactional_conversion`
  - `simd_json.projection_engine.single_beam_boundary`
  - `simd_json.projection_engine.internal_phase_timing`
  - `simd_json.projection_execution.threaded_projection`
  - `simd_json.projection_execution.one_correlated_operation`
  - `simd_json.projection_execution.owner_first_admission`
  - `simd_json.projection_execution.exclusive_document_selection`
  - `simd_json.projection_execution.committed_consumption`
  - `simd_json.projection_execution.preadmission_nonconsumption`
  - `simd_json.projection_execution.generation_and_resource_retention`
  - `simd_json.projection_execution.binary_temporary_document`
  - `simd_json.projection_execution.close_interlock`
  - `simd_json.projection_execution.cancellation_boundaries`
  - `simd_json.projection_execution.native_memory_baseline`

## 4.1 Section — Correlated Threaded Projection Operation

- [ ] 4.1 Section - Admit one validated projection as one retained,
  uniquely-correlated Zigler-threaded operation.

  This section extends the qualified Milestone 1 coordinator without creating a
  second execution runtime or using normal and dirty schedulers for
  input-dependent work.

  - [ ] 4.1.1 Task - Add the projection operation kind and payload.

    The task packages the normalized projection and either binary or document
    source into state owned by the stable coordinator through completion.

    - [ ] 4.1.1.1 Subtask - Extend the internal threaded operation union with a projection kind, source discriminator, normalized descriptor ownership, request reference, generation, caller monitor, cancellation flag, and private result environment.
    - [ ] 4.1.1.2 Subtask - Retain every source binary term or document resource before submission and keep its projection arenas, plan, slots, and result environment reachable until terminal cleanup.
    - [ ] 4.1.1.3 Subtask - Submit exactly one Zigler-threaded worker and prohibit ordinary-NIF, dirty-NIF, inline parse, public-open chaining, or per-path fallback when admission fails.
    - [ ] 4.1.1.4 Subtask - Extend correlation matching so only the projection's kind/reference/generation tuple can complete its waiting caller.

  - [ ] 4.1.2 Task - Handle terminal, late, and orphaned results.

    The task reuses coordinator ownership and makes every non-delivered result
    release the same complete native and private-environment graph.

    - [ ] 4.1.2.1 Subtask - Deliver only one complete success map or one translated error after reference, operation kind, caller monitor, and generation checks succeed.
    - [ ] 4.1.2.2 Subtask - Discard late, duplicate, stale, mismatched, cancelled, timed-out, or caller-orphaned results only after plan, slots, terms, environments, and retained sources are released.
    - [ ] 4.1.2.3 Subtask - Add deterministic boundary controls before plan compilation, before cursor access, during traversal, before term construction, during conversion, and before delivery.

## 4.2 Section — One-Shot Document Admission and Close Interlock

- [ ] 4.2 Section - Add a generation-checked single-use projection state beside
  the existing document lifecycle.

  This section makes cursor behavior deterministic under valid attempts,
  invalid preflight, submission rejection, close, GC, cancellation, caller
  death, and shutdown.

  - [ ] 4.2.1 Task - Implement owner-first projection reservation.

    The task atomically reserves one fresh document without disclosing state to
    another process or publishing raw resource internals.

    - [ ] 4.2.1.1 Subtask - Add private `fresh`, `selecting`, and `consumed` projection states without changing the monotonic `open`, `closing`, and `closed` lifecycle.
    - [ ] 4.2.1.2 Subtask - Validate the registered document resource and immutable owner before reading lifecycle, generation, or projection state.
    - [ ] 4.2.1.3 Subtask - Reserve `fresh -> selecting` with one atomic winner, capture the active generation, and reject any second owner attempt as `cursor_consumed` without cursor access.
    - [ ] 4.2.1.4 Subtask - Ensure a non-owner receives `not_owner` for fresh, selecting, consumed, closing, and closed documents without mutation or state disclosure.

  - [ ] 4.2.2 Task - Commit or roll back consumption at exact boundaries.

    The task distinguishes a failure that provably never started a worker from
    every outcome after native cursor access is possible.

    - [ ] 4.2.2.1 Subtask - Leave the document fresh for invalid projection, invalid source, non-owner, closed-resource, and other pre-reservation failures.
    - [ ] 4.2.2.2 Subtask - On submission rejection, roll `selecting` back to `fresh` only after proving no worker owns or can observe the reservation and release every retained admission object.
    - [ ] 4.2.2.3 Subtask - Mark the reservation committed before first cursor access and finish in `consumed` for success, path/type/parse/range failure, cancellation, caller death, conversion failure, and internal failure.
    - [ ] 4.2.2.4 Subtask - Validate the captured generation before every native dereference and before delivery; generation mismatch cancels and discards instead of touching stale state.

  - [ ] 4.2.3 Task - Interlock projection with cleanup.

    The task prevents close and resource destruction from racing active traversal
    or borrowed result strings.

    - [ ] 4.2.3.1 Subtask - Make close and shutdown prevent new reservations, request cancellation of selecting work, and join its safe terminal boundary through the existing off-scheduler cleanup path.
    - [ ] 4.2.3.2 Subtask - Retain document, parser, padded input, plan, borrowed strings, slots, and result environment until selection delivery or discard finishes.
    - [ ] 4.2.3.3 Subtask - Keep the resource destructor callback bounded to detach/handoff and route all potentially large projection cleanup through the existing cleanup-only dispatcher.
    - [ ] 4.2.3.4 Subtask - Preserve owner `close/1` idempotence for fresh and consumed documents and exactly-once reverse document destruction after selection quiesces.

## 4.3 Section — Binary Temporary Documents and BEAM Result Conversion

- [ ] 4.3 Section - Own binary-source parsing and complete transactional term
  construction inside the same worker operation.

  This section makes returned maps independent of native input while avoiding a
  public temporary document or an extra open/select/close request sequence.

  - [ ] 4.3.1 Task - Implement the binary projection lifetime graph.

    The task creates and releases every temporary object on the worker using the
    Milestone 1 padded-copy and exception-safe ABI contracts.

    - [ ] 4.3.1.1 Subtask - After preflight, create the aligned padded input, parser, On-Demand document, projection plan, and slots inside one correlated worker without publishing a document resource.
    - [ ] 4.3.1.2 Subtask - Traverse and validate through the same Phase 3 engine used by document selection rather than introducing a second parser or lookup path.
    - [ ] 4.3.1.3 Subtask - Destroy slots, plan, document, parser, and padded input in dependency-safe order before terminal delivery on success and every failure path.
    - [ ] 4.3.1.4 Subtask - Handle caller death, submission failure, cancellation, conversion allocation failure, and shutdown with exactly the same retained ownership and cleanup guarantees.

  - [ ] 4.3.2 Task - Construct one complete BEAM result map.

    The task converts validated native slots only after traversal succeeds and
    never lets a source-backed value cross the operation boundary.

    - [ ] 4.3.2.1 Subtask - Build exact signed/unsigned BEAM integers, finite floats, booleans, nil, and fresh binaries in an operation-owned private environment.
    - [ ] 4.3.2.2 Subtask - Copy every borrowed string before releasing or closing its source document and prove the result retains neither document resource nor source binary.
    - [ ] 4.3.2.3 Subtask - Associate values with exact caller atom/binary output keys and build the map only after every slot converts successfully.
    - [ ] 4.3.2.4 Subtask - Chunk large conversion loops with cancellation checks and discard the complete private environment on any later failure so no partial map escapes.

  - [ ] 4.3.3 Task - Extend bounded diagnostics and accounting.

    The task gives integration and qualification tests enough visibility to
    prove scheduling, single-boundary execution, phase timing, and cleanup.

    - [ ] 4.3.3.1 Subtask - Add test-only gauges for projection operations, plans, slots, private environments, retained documents/binaries, and completed/discarded deliveries.
    - [ ] 4.3.3.2 Subtask - Record redacted compilation, traversal, and term-construction durations plus worker-entry and boundary counts without source keys, paths, values, addresses, or public telemetry.
    - [ ] 4.3.3.3 Subtask - Extend quiescence helpers so tests can await all projection work and failed callback handoff retries before comparing baselines.

## 4.4 Section — Phase 4 Integration Tests

- [ ] 4.4 Section - Prove threaded correlation, binary and document lifetimes,
  deterministic consumption, cancellation, close interlock, and native baseline
  recovery through private integration seams.

  This section closes the complete internal vertical slice before Phase 5 adds
  a public function.

  - [ ] 4.4.1 Task - Run binary and document operation matrices.

    The task executes real native plans through the coordinator with controlled
    source, ownership, state, result ordering, and failure boundaries.

    - [ ] 4.4.1.1 Subtask - Run concurrent binary and document projections whose results finish out of order and assert exact kind/reference/generation correlation and one request boundary per call.
    - [ ] 4.4.1.2 Subtask - Prove invalid preflight and rejected submission leave a document fresh, while success and every post-cursor failure leave it consumed and later selection returns `cursor_consumed`.
    - [ ] 4.4.1.3 Subtask - Exercise owner and non-owner selection across every document state and assert owner-first errors, no unauthorized mutation, and idempotent owner close.
    - [ ] 4.4.1.4 Subtask - Drop original input and temporary terms, force GC, and prove completed scalar maps and copied strings remain valid with no retained source/document reference.

  - [ ] 4.4.2 Task - Run cancellation, teardown, and scheduler integration gates.

    The task attacks caller death, close, GC, submission, callback handoff, and
    application-generation races while independent BEAM work measures latency.

    - [ ] 4.4.2.1 Subtask - Kill callers at every projection cancellation boundary for binary and document sources and assert no orphan or stale delivery.
    - [ ] 4.4.2.2 Subtask - Race selecting documents with close, GC, application stop/start, rejected cleanup submission, and callback handoff retry; require one safe cleanup and generation isolation.
    - [ ] 4.4.2.3 Subtask - Project large valid, malformed, and missing-path inputs concurrently while heartbeats run; assert worker entry and no ordinary/dirty fallback, using a preliminary non-regression threshold pending Phase 6 qualification.
    - [ ] 4.4.2.4 Subtask - Await quiescence after every batch and require all document, input, plan, slot, environment, operation, retained-resource, and failed-handoff gauges at baseline.
    - [ ] 4.4.2.5 Subtask - Run focused threaded projection tests, the NIF sanitizer suite, all Milestone 1 lifecycle/scheduler tests, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 4 complete.
