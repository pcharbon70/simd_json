# Phase 4 — Threaded Execution and Safe Teardown

Back to plan: [README](./README.md)

- [ ] 4 Phase - Connect document construction and destruction to correlated Zigler-threaded work outside normal and dirty schedulers.

  This phase creates the Milestone 1 execution substrate. Ordinary NIF entry is
  restricted to bounded validation, retention, state transition, request setup,
  and submission; the padded copy, simdjson parse, and potentially large cleanup
  run through the pinned threaded mechanism. Caller death, late results, GC,
  shutdown, and unload all preserve ownership until exactly-once cleanup reaches
  a safe terminal state. This remains a qualification mechanism, not the final
  bounded worker pool promised by Milestone 4.

  Contract focus:

  - `simd_json.native_execution.threaded_parse`
  - `simd_json.native_execution.bounded_nif_entry`
  - `simd_json.native_execution.no_fallback`
  - `simd_json.native_execution.request_correlation`
  - `simd_json.native_execution.retained_resources`
  - `simd_json.native_execution.late_result_cleanup`
  - `simd_json.native_execution.cancellation_boundaries`
  - `simd_json.native_execution.threaded_cleanup`
  - `simd_json.native_execution.scheduler_qualification`
  - `simd_json.native_execution.preproduction_boundary`
  - `simd_json.native_execution.shutdown_cleanup`
  - `simd_json.document_resource.deferred_large_cleanup`
  - `simd_json.document_resource.gc_cleanup`
  - `simd_json.native_execution.large_parse_responsiveness`
  - `simd_json.native_execution.caller_dies_while_running`
  - `simd_json.native_execution.result_reference_mismatch`
  - `simd_json.native_execution.threaded_submission_failure`
  - `simd_json.native_execution.large_gc_teardown`
  - `simd_json.native_execution.reload_cleanup`

## 4.1 Section — Bounded Admission and Request Correlation

- [x] 4.1 Section - Define one bounded NIF admission protocol for every input-dependent operation.

  This section verifies the exact semantics of the pinned Zigler `:threaded`
  facility and wraps them in an operation record whose references, caller,
  resource retention, and terminal state cannot be confused with another call.

  - [x] 4.1.1 Task - Verify and encapsulate the pinned threaded runtime.

    The task confirms which Zigler and Erlang NIF APIs are legal on the calling
    scheduler, worker thread, completion path, resource callback, upgrade, and
    unload path before those APIs own real document memory.

    - [x] 4.1.1.1 Subtask - Add a focused threaded smoke test that records calling-process identity and scheduler classification at admission, worker execution, and completion.
    - [x] 4.1.1.2 Subtask - Document which environment, term, binary, resource, and message APIs the pinned Zigler/OTP combination permits from each execution context.
    - [x] 4.1.1.3 Subtask - Encapsulate Zigler-specific threaded submission behind one native operation adapter so later Milestone 4 replacement does not change document ownership semantics.
    - [x] 4.1.1.4 Subtask - If the pinned facility cannot safely submit both parse and deferred cleanup work, stop and reconcile the execution ADR rather than falling back to a normal or dirty NIF.

  - [x] 4.1.2 Task - Implement the correlated operation record.

    The task gives each admitted parse or cleanup operation unique identity and
    explicit ownership from admission through delivery or discard.

    - [x] 4.1.2.1 Subtask - Generate an unforgeable BEAM reference for each request and pair it with a private operation kind and native generation.
    - [x] 4.1.2.2 Subtask - Retain the caller identity, required resource references, input ownership, and any private result environment until terminal cleanup.
    - [x] 4.1.2.3 Subtask - Represent queued, running, cancelling, delivering, completed, and discarded terminal paths without allowing two terminal owners.
    - [x] 4.1.2.4 Subtask - Add bounded test accounting for live operation records, retained resources, queued cleanup, delivered results, and discarded results.

  - [x] 4.1.3 Task - Restrict ordinary NIF entry to bounded work.

    The task makes scheduler safety structural rather than dependent on typical
    input size.

    - [x] 4.1.3.1 Subtask - Limit admission to argument shape checks, resource type checks, owner/lifecycle snapshots, reference creation, required retention, atomic state changes, and threaded submission.
    - [x] 4.1.3.2 Subtask - Move input copying, padding initialization, simdjson parsing, unbounded result preparation, waits, and native destruction out of ordinary callbacks.
    - [x] 4.1.3.3 Subtask - On submission failure, return an internal structured status and release retained state without executing any input-dependent fallback.
    - [x] 4.1.3.4 Subtask - Add source-level and runtime test hooks that fail if parse work is registered as synchronous, dirty CPU, or dirty IO execution.

## 4.2 Section — Threaded Parse, Cancellation, and Delivery

- [ ] 4.2 Section - Run padded-copy construction and simdjson parsing as one retained threaded operation.

  This section connects the resource foundation to real parsing while ensuring
  caller loss or result races cannot invalidate memory or deliver a result to
  the wrong process.

  - [x] 4.2.1 Task - Implement the threaded document-open operation.

    The task constructs all input-dependent native state on the threaded path
    and publishes an opaque resource only after complete success.

    - [x] 4.2.1.1 Subtask - Retain or safely transfer the input bytes needed by the worker before ordinary admission returns.
    - [x] 4.2.1.2 Subtask - On the worker, allocate and initialize the owned padded copy, create parser/document handles through the C ABI, and populate the resource in rollback-safe order.
    - [x] 4.2.1.3 Subtask - Capture the opening process as owner and publish `open` lifecycle state only after input, handles, owner, generation, and cleanup metadata are complete.
    - [x] 4.2.1.4 Subtask - Return only bounded success metadata needed to construct the opaque resource term or a stable internal status needed by the Elixir error layer.

  - [ ] 4.2.2 Task - Add cancellation boundaries and safe uninterruptible retention.

    The task prevents avoidable work after the caller or runtime no longer wants
    a result while accepting that one simdjson call may run to its next safe
    boundary.

    - [x] 4.2.2.1 Subtask - Check cancellation before padded-copy construction, immediately before parsing, immediately after parsing, before result-term construction, and before delivery.
    - [x] 4.2.2.2 Subtask - Keep input, operation, and resource state retained for the complete duration of any uninterruptible simdjson call.
    - [ ] 4.2.2.3 Subtask - Mark operations cancelled on caller death, explicit lifecycle closure, application shutdown, or unload when the verified native boundary permits it.
    - [x] 4.2.2.4 Subtask - Route every cancellation boundary through the same rollback or resource cleanup owner used for ordinary failure.

  - [x] 4.2.3 Task - Correlate delivery and clean every orphan result.

    The task ensures only the waiting request can consume its completion and that
    discarded completions cannot leak native allocations or private term
    environments.

    - [x] 4.2.3.1 Subtask - Tag completion messages with the private operation kind, unique reference, and native generation, and match all three before completing a caller.
    - [x] 4.2.3.2 Subtask - Treat late, duplicate, forged, mismatched, cancelled, timed-out, and caller-orphaned completions as discard paths rather than alternate successes.
    - [x] 4.2.3.3 Subtask - Release every result environment, document resource, input retention, operation record, and temporary buffer owned by a discarded completion.
    - [x] 4.2.3.4 Subtask - Prevent a stale completion from crossing a NIF upgrade or unload generation and from remaining as an unbounded unmatched caller-mailbox message.

## 4.3 Section — Explicit, GC, Shutdown, and Unload Teardown

- [ ] 4.3 Section - Route every potentially large destruction path through one off-scheduler cleanup operation.

  This section attaches the Phase 3 cleanup state machine to threaded execution.
  Explicit close can wait outside a normal scheduler for completion; a resource
  destructor atomically detaches and enqueues cleanup, then returns while native
  retention keeps the operation alive.

  - [ ] 4.3.1 Task - Implement shared threaded cleanup admission.

    The task lets explicit close, GC, partial open, caller death, and shutdown
    compete for one cleanup owner without duplicating destruction code.

    - [ ] 4.3.1.1 Subtask - Atomically transition the resource from `open` to `closing`, reject new operation admission, and invalidate its generation before cleanup submission.
    - [ ] 4.3.1.2 Subtask - Make every later close or destructor path join, observe, or retain the already-admitted cleanup instead of destroying state again.
    - [ ] 4.3.1.3 Subtask - Wait for already-admitted native work at safe boundaries without blocking a normal scheduler, then perform reverse destruction on the threaded path.
    - [ ] 4.3.1.4 Subtask - Publish `closed` and wake explicit close waiters only after document, parser, padded input, and operation-owned allocations are released.

  - [ ] 4.3.2 Task - Keep resource callbacks bounded and GC cleanup retained.

    The task makes garbage collection a safe fallback without turning the
    resource destructor into a second, scheduler-blocking cleanup engine.

    - [ ] 4.3.2.1 Subtask - Restrict the destructor callback to bounded state transition, ownership detachment, retained cleanup creation, and verified threaded submission.
    - [ ] 4.3.2.2 Subtask - Keep resource metadata alive after the callback returns until threaded destruction records `closed` and releases the final retention.
    - [ ] 4.3.2.3 Subtask - Define a fail-closed path for cleanup submission failure during GC that preserves memory safety and never performs unbounded normal-scheduler teardown.

  - [ ] 4.3.3 Task - Implement application shutdown and NIF unload quiescence.

    The task prevents code or module state from unloading while queued or
    running work can still call it.

    - [ ] 4.3.3.1 Subtask - Introduce a native generation and shutdown state that rejects new admission once application stop, upgrade, or unload begins.
    - [ ] 4.3.3.2 Subtask - Cancel queued work, retain running work to its next safe boundary, suppress delivery, and drain all cleanup operations before unload releases module state.
    - [ ] 4.3.3.3 Subtask - Make repeated load and upgrade initialize a fresh generation that cannot accept completions from the prior artifact.
    - [ ] 4.3.3.4 Subtask - Record any OTP environment where repeated unload cannot be exercised and keep that target unqualified until equivalent evidence is available.

## 4.4 Section — Phase 4 Integration Tests

- [ ] 4.4 Section - Prove threaded correlation, cancellation, cleanup, and scheduler isolation under races.

  This section closes the execution substrate before the public Elixir API is
  allowed to depend on it. Phase 6 repeats scheduler measurements with the final
  public surface and formal qualification budget.

  - [ ] 4.4.1 Task - Run request-correlation and failure-path integration tests.

    The task executes `caller_dies_while_running`,
    `result_reference_mismatch`, and `threaded_submission_failure` with native
    counters and deterministic synchronization seams.

    - [ ] 4.4.1.1 Subtask - Complete concurrent requests in reverse order and assert each caller accepts only its own reference and generation.
    - [ ] 4.4.1.2 Subtask - Inject forged, duplicate, late, and stale-generation completions and assert none completes another call or leaks result-owned state.
    - [ ] 4.4.1.3 Subtask - Terminate callers before parse, during an uninterruptible parse, after parse, and before delivery; assert safe cancellation and baseline recovery.
    - [ ] 4.4.1.4 Subtask - Reject threaded submission for parse and cleanup in controlled tests and prove there is no normal or dirty scheduler fallback.

  - [ ] 4.4.2 Task - Run cleanup, reload, and preliminary scheduler integration tests.

    The task executes `large_gc_teardown`, `reload_cleanup`, and an initial
    `large_parse_responsiveness` matrix through the internal document operation.

    - [ ] 4.4.2.1 Subtask - Trigger GC for multiple large resources and assert callbacks stay bounded while threaded cleanup returns every native counter to baseline.
    - [ ] 4.4.2.2 Subtask - Repeatedly load and unload in supported test environments with queued, running, completed, and abandoned operations; assert no stale delivery or retained allocation survives.
    - [ ] 4.4.2.3 Subtask - Run large valid and invalid parses while BEAM heartbeat processes sample wake-up latency and normal/dirty scheduler utilization.
    - [ ] 4.4.2.4 Subtask - Assert parser work never executes in ordinary or dirty NIF contexts and document that final admission control remains deferred to Milestone 4.
    - [ ] 4.4.2.5 Subtask - Run the focused execution tests, `mix test`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 4 complete.
