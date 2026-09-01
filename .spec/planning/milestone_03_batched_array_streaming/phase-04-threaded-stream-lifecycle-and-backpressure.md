# Phase 4 — Threaded Stream Lifecycle and Backpressure

Back to plan: [README](./README.md)

- [ ] 4 Phase - Connect lazy cursor setup and bounded batches to the correlated
  threaded runtime, implement select/stream document exclusion, and prove
  demand-driven cleanup through private integration seams.

  This phase makes ABI v3 reachable only internally. It creates one setup
  operation and one operation per demanded batch, retains binary or document
  graphs across idle time, admits at most one batch, performs no prefetch, and
  cancels safely on halt, exception, death, close, GC, or shutdown. Phase 5
  owns the public Enumerable.

  Contract focus:

  - `simd_json.stream_execution.lazy_setup`
  - `simd_json.stream_execution.threaded_stream_work`
  - `simd_json.stream_execution.correlated_batch_operations`
  - `simd_json.stream_execution.owner_first_admission`
  - `simd_json.stream_execution.exclusive_document_cursor`
  - `simd_json.stream_execution.document_consumption`
  - `simd_json.stream_execution.binary_cursor_graph`
  - `simd_json.stream_execution.cursor_state_machine`
  - `simd_json.stream_execution.single_in_flight_batch`
  - `simd_json.stream_execution.no_prefetch`
  - `simd_json.stream_execution.generation_and_retention`
  - `simd_json.stream_execution.early_halt_cleanup`
  - `simd_json.stream_execution.cancellation_boundaries`
  - `simd_json.stream_execution.close_shutdown_interlock`
  - `simd_json.stream_execution.native_memory_baseline`

## 4.1 Section — Lazy Setup and Correlated Batch Operations

- [ ] 4.1 Section - Admit stream setup only from reduction and execute each
  requested batch as one retained, uniquely correlated Zigler-threaded job.

  This section extends the existing stable coordinator rather than adding a
  second runtime or using normal and dirty schedulers for input-dependent work.

  - [ ] 4.1.1 Task - Add setup and batch operation kinds.

    The task packages normalized options, source, cursor generation, batch
    sequence, cancellation, and private result environments under coordinator
    ownership.

    - [ ] 4.1.1.1 Subtask - Extend the operation union with stream-setup and stream-batch kinds containing source discriminator, normalized target/fields/limits, owner, cursor resource, request reference, generation, sequence, monitor, cancellation, and result environment.
    - [ ] 4.1.1.2 Subtask - Invoke setup only from the private reduction-start seam and prove constructing, inspecting, copying, or garbage-collecting an unreduced shell admits no operation.
    - [ ] 4.1.1.3 Subtask - Submit setup and each batch as exactly one Zigler-threaded worker and prohibit ordinary, dirty, inline, public-open chaining, per-row, and per-field fallback.
    - [ ] 4.1.1.4 Subtask - Match completion only on operation kind, unforgeable reference, cursor generation, batch sequence, owner monitor, and active application generation.

  - [ ] 4.1.2 Task - Deliver or discard bounded batch results safely.

    The task builds one complete source-ordered list of row maps per native
    success and releases the same graph for every undeliverable result.

    - [ ] 4.1.2.1 Subtask - Convert only ABI-committed native rows into exact-key scalar maps in a private environment, copy strings, and transfer one complete bounded list plus done metadata at join.
    - [ ] 4.1.2.2 Subtask - Translate native failure into bounded internal error metadata and discard every partial row, map, list, copied binary, environment, and batch allocation before completion.
    - [ ] 4.1.2.3 Subtask - Discard late, duplicate, stale, mismatched, cancelled, timed-out, or caller-orphaned setup/batch results only after cursor and operation ownership reaches a safe terminal state.
    - [ ] 4.1.2.4 Subtask - Add deterministic pause controls before setup, target access, each batch, between rows, during projection, before/during conversion, before delivery, during final validation, and before done delivery.

## 4.2 Section — Source Graphs and One-Shot Document Admission

- [ ] 4.2 Section - Retain one binary or document source graph across batches
  and make selection and streaming mutually exclusive cursor commitments.

  This section generalizes the existing document reservation without changing
  owner-first, generation, lifecycle, or exactly-once close guarantees.

  - [ ] 4.2.1 Task - Implement the binary stream graph.

    The task creates one unpublished document and cursor at lazy start and
    retains it until terminal cleanup rather than reopening for each batch.

    - [ ] 4.2.1.1 Subtask - On setup worker, create aligned padded input, parser, On-Demand document, row projection plan, and stream cursor through the accepted constructors without publishing a document.
    - [ ] 4.2.1.2 Subtask - Retain the graph while the consumer processes batches and prove no parser, projection, allocation, or message activity occurs during idle periods.
    - [ ] 4.2.1.3 Subtask - Destroy current batch, cursor, plan, document, parser, and input in reverse dependency order on done, setup/batch error, early halt, exception, caller death, GC, or shutdown.
    - [ ] 4.2.1.4 Subtask - Keep every completed row and copied string valid after graph destruction and prove no returned term retains the original source binary unintentionally.

  - [ ] 4.2.2 Task - Implement owner-first document stream reservation.

    The task allows exactly one select or stream use and defines rollback and
    commitment at the existing cursor-access boundary.

    - [ ] 4.2.2.1 Subtask - Extend private document use state to `fresh -> selecting -> consumed` or `fresh -> streaming -> consumed` while preserving `open -> closing -> closed` lifecycle.
    - [ ] 4.2.2.2 Subtask - Validate registered resource and immutable owner before lifecycle, generation, use state, reservation, setup request, or cursor disclosure.
    - [ ] 4.2.2.3 Subtask - Roll a rejected setup reservation back to fresh only after proving no worker can observe it; otherwise commit immediately before first target cursor access.
    - [ ] 4.2.2.4 Subtask - Finish committed setup, every batch, done, error, cancellation, early halt, consumer failure/death, close, and shutdown as consumed without rewind or transparent reparse.

  - [ ] 4.2.3 Task - Interlock parent close and generation changes.

    The task prevents document destruction or application generation advance
    from invalidating active cursor and batch work.

    - [ ] 4.2.3.1 Subtask - Retain document, parser, input, cursor, plan, batch, private environment, and operation across every native dereference, conversion, delivery, and discard.
    - [ ] 4.2.3.2 Subtask - Validate captured document and application generations before setup access, batch access, final validation, delivery, and done transition.
    - [ ] 4.2.3.3 Subtask - Make close and shutdown prevent new batches, request cancellation, join or transfer active work off scheduler, close cursor first, and then run existing document destruction exactly once.
    - [ ] 4.2.3.4 Subtask - Keep resource callbacks bounded to detach/handoff and reuse the cleanup-only dispatcher and failed-handoff retry ownership without parsing remaining input.

## 4.3 Section — Demand Backpressure, Early Halt, and Accounting

- [ ] 4.3 Section - Enforce one active and one returned batch, perform no
  prefetch, and close promptly for every reducer terminal path.

  This section turns consumer demand into local backpressure and provides
  bounded test visibility without claiming Milestone 4 global admission.

  - [ ] 4.3.1 Task - Serialize batch demand per cursor.

    The task prevents concurrent advancement and delays the next request until
    the BEAM has consumed or abandoned the current result list.

    - [ ] 4.3.1.1 Subtask - Reserve `ready -> running` atomically for one batch sequence and reject overlapping next calls without native parser access.
    - [ ] 4.3.1.2 Subtask - Return to ready only after successful non-final delivery ownership is established; move terminal results monotonically to done, cancelled, or closed.
    - [ ] 4.3.1.3 Subtask - Hold one returned batch in private Enumerable state and prohibit submitting another until its list is exhausted or reduction terminates.
    - [ ] 4.3.1.4 Subtask - Add slow-consumer controls proving cursor index, operation count, allocation gauges, and stream-specific mailbox messages do not advance during pauses.

  - [ ] 4.3.2 Task - Implement deterministic early-halt cleanup.

    The task makes ordinary reducer control flow and exceptional termination
    converge before native resources can be abandoned.

    - [ ] 4.3.2.1 Subtask - Add private halt handling for normal completion, explicit halt, `Enum.take`, `Enum.find`, consumer callback exception, and owner process death.
    - [ ] 4.3.2.2 Subtask - Mark cancellation before another batch, cancel or safely join an in-flight worker, close cursor without final traversal, and preserve the original consumer exception after cleanup.
    - [ ] 4.3.2.3 Subtask - Assert early halt does not increment row traversal beyond already admitted work, perform final document validation, or read an unconsumed unique source marker.
    - [ ] 4.3.2.4 Subtask - Make repeated halt, done cleanup, error cleanup, GC fallback, close, and shutdown converge on one idempotent terminal owner.

  - [ ] 4.3.3 Task - Extend diagnostics, quiescence, and pre-production labels.

    The task makes local demand, worker boundaries, cancellation latency, and
    full graph recovery observable only to tests and qualification.

    - [ ] 4.3.3.1 Subtask - Add test-only gauges for stream shells, setup/batch operations, cursors, frames, plans, batches, rows, slots, copied strings, environments, retained inputs/documents, deliveries, discards, and halt cleanups.
    - [ ] 4.3.3.2 Subtask - Record redacted setup, queue, target, row, conversion, consumer-idle, cancellation, cleanup, batch-size, encoded-byte, and boundary data without source, paths, keys, values, PIDs, or addresses.
    - [ ] 4.3.3.3 Subtask - Extend quiescence helpers to await every stream operation and callback retry before baseline comparison and keep all diagnostics absent from production builds.
    - [ ] 4.3.3.4 Subtask - Label one-in-flight demand as per-stream backpressure and preserve explicit deferral of global capacity, worker pool, public cancellation registry, and telemetry to Milestone 4.

## 4.4 Section — Phase 4 Integration Tests

- [ ] 4.4 Section - Prove lazy setup, batch correlation, source lifetimes,
  one-shot exclusion, slow-consumer demand, cancellation, early halt,
  close/shutdown interlock, scheduler isolation, and baseline recovery through
  private seams.

  This section closes the complete internal vertical slice before Phase 5 adds
  public Enumerable behavior.

  - [ ] 4.4.1 Task - Run binary and document lifecycle matrices.

    The task executes real ABI v3 batches through the coordinator with
    controlled sources, owner/state, ordering, limits, and failures.

    - [ ] 4.4.1.1 Subtask - Construct unreduced shells and assert zero native delta, then run concurrent binary and document streams finishing batches out of order with exact kind/reference/generation/sequence correlation.
    - [ ] 4.4.1.2 Subtask - Prove invalid preflight and rejected setup leave a document fresh, while select/stream races admit one winner and every post-access stream outcome leaves consumed.
    - [ ] 4.4.1.3 Subtask - Exercise owner and non-owner setup, batch, halt, and cleanup across every document/cursor state with owner-first errors and idempotent close.
    - [ ] 4.4.1.4 Subtask - Drop source and parent terms, pause between thousands of batches, force GC, and prove copied rows remain valid while retained native graphs stay bounded and eventually return to baseline.

  - [ ] 4.4.2 Task - Run demand, cancellation, teardown, and scheduler gates.

    The task attacks every consumer and runtime boundary while independent BEAM
    work measures responsiveness.

    - [ ] 4.4.2.1 Subtask - Pause slow consumers within and between batches and require one active/returned batch, no prefetch, stable cursor position, bounded mailbox, and exact operation counts.
    - [ ] 4.4.2.2 Subtask - Halt, raise, and kill callers at every setup, target, row, projection, conversion, final-validation, and delivery boundary; assert no orphan, stale batch, or remainder scan.
    - [ ] 4.4.2.3 Subtask - Race active streams with document close, GC, application stop/start, submission rejection, cleanup handoff retry, and generation change; require one cleanup owner and no stale dereference or delivery.
    - [ ] 4.4.2.4 Subtask - Stream large valid, malformed, wrong-type, byte-limited, slow, and cancelled inputs concurrently with heartbeats; require threaded entries and no ordinary/dirty fallback under preliminary thresholds.
    - [ ] 4.4.2.5 Subtask - Await quiescence after every batch family and require all document, cursor, frame, plan, row, slot, string, batch, environment, operation, retained-resource, dispatcher, and failed-handoff gauges at baseline.
    - [ ] 4.4.2.6 Subtask - Run focused threaded stream tests, NIF sanitizer and every Milestone 1/2 lifecycle/scheduler gate, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 4 complete.
