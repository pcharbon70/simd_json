# Stream Execution and Lifecycle

Milestone 4 Phase 5 routes lazy setup and every demanded batch through the
bounded native pool. Early halt closes without prefetch and leaves no queued
or running stream job.

Milestone 4 Phase 4 proved the pool primitives that Phase 5 now applies to
stream jobs while preserving cursor demand, batch ownership, and cancellation.

Current-truth contract for Milestone 3 lazy cursor setup, correlated
threaded batches, per-stream demand backpressure, document consumption,
cancellation, deterministic cleanup, scheduler qualification, and ETL evidence.

## Intent

This subject makes a long-lived forward-only stream safe across idle consumer
time and repeated native operations. It ensures only the owner can advance one
cursor, at most one batch is active and one is being consumed, early halt does
not scan the remainder, and every terminal path releases the retained source
graph without claiming Milestone 4's production worker pool.

Phase 1 implements the pre-admission side of lazy setup. An undocumented opaque
term captures the constructing PID and retains a binary or genuine document
plus completely normalized options without parsing JSON, reserving a document,
creating a request, or changing native state. Test-only setup and batch
admission counters remain zero, and document owner/lifecycle failures are
deferred to future reduction. No execution or cleanup graph exists yet, so the
complete bootstrap exception remains in force.

Phase 2 establishes only the cursor/parent ownership primitive needed by later
setup. It does not admit a stream request, reserve a document, traverse a
target, start a threaded batch, construct a public Enumerable, or create a
cleanup coordinator graph.

Phase 3 implements forward-only traversal and transactional batches only
inside the private native cursor. It adds no threaded admission, demand,
prefetch, owner-reduction, or cleanup-coordinator behavior; those execution
claims remain planned for Phase 4.

Phase 4 connects that cursor to the existing correlated Zigler-threaded
coordinator through private test seams. Distinct setup and batch operations
carry request, application-generation, cursor-generation, and batch-sequence
identity; caller death and stale completion discard converge on the existing
coordinator owner. Binary setup retains one unpublished input/parser/document/
plan/cursor graph, while document setup atomically reserves the shared
fresh/selecting/streaming/consumed state and transfers its cleanup interlock to
the cursor resource. Each demand admits one native ABI v3 batch, copies its
complete row maps through a private join environment, advances the sequence
only after delivery ownership, and performs no work while the consumer is
idle. Test-only accounting exposes live setup/batch operations, worker entries,
deliveries, discards, cursors, and retained parents; no public Enumerable or
production pool surface is added before Phase 5 and Milestone 4 respectively.

Milestone 3 Phase 5 binds public reduction to the constructing owner, performs lazy setup on first demand, retains at most one returned batch, requests no next batch until its rows are consumed, and closes deterministically on done, halt, reducer exception, or runtime failure.

Milestone 4 Phase 1 validates finite future worker and queue capacity before
coordinator startup. It does not add global admission, prefetch, parallel cursor
work, pool cancellation, or telemetry, so all Milestone 3 per-stream demand and
pre-production execution boundaries remain unchanged.

```spec-meta
id: simd_json.stream_execution
kind: subsystem
status: active
summary: Milestone 3 runs lazy array setup and demand-driven batches off scheduler with one-owner state, no prefetch, prompt halt, and qualified bounded memory.
surface:
  - native/**
  - lib/simd_json/**/*.ex
  - test/**/*stream*
  - test/**/*scheduler*
  - test/qualification/**
  - bench/**/*stream*
  - docs/milestones/03-batched-array-streaming.md
decisions:
  - simd_json.document_resource_and_buffer_ownership
  - simd_json.off_scheduler_native_execution
  - simd_json.projection_admission_consumption_and_lifetime
  - simd_json.stream_ownership_backpressure_and_lifetime
  - simd_json.forward_only_batched_array_cursor
  - simd_json.lazy_stream_api_and_bounded_options
  - simd_json.owned_native_jobs_and_bounded_fifo
  - simd_json.monitored_delivery_and_resource_serialization
```

## Requirements

```spec-requirements
- id: simd_json.stream_execution.lazy_setup
  statement: Native source opening, document reservation, target lookup, plan compilation, and cursor construction shall begin only when the owner reduces the stream, and an unreduced stream shall create no native progress or cleanup obligation.
  priority: must
  stability: stable

- id: simd_json.stream_execution.threaded_stream_work
  statement: Input-dependent setup, target traversal, row projection, batch conversion, final validation, and potentially large cleanup shall execute through the correlated Zigler-threaded path rather than an ordinary or dirty CPU NIF.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.correlated_batch_operations
  statement: Cursor setup and each next-batch request shall use distinct unforgeable kind, reference, cursor-generation, and batch-sequence correlation and shall produce exactly one terminal result whose late, stale, duplicate, mismatched, cancelled, or orphaned form is safely discarded.
  priority: must
  stability: stable

- id: simd_json.stream_execution.owner_first_admission
  statement: Stream setup, batch advancement, and cleanup shall validate the constructing PID and any genuine document owner before revealing lifecycle, cursor, reservation, generation, or consumed state.
  priority: must
  stability: stable

- id: simd_json.stream_execution.exclusive_document_cursor
  statement: A fresh document shall atomically admit at most one selecting or streaming operation, and selection and streaming shall be mutually exclusive uses of the same forward-only cursor.
  priority: must
  stability: stable

- id: simd_json.stream_execution.document_consumption
  statement: Invalid construction and proven pre-worker rejection shall leave a document fresh, while every stream outcome after first target cursor access including success, error, cancellation, early halt, consumer failure, close, or shutdown shall leave it consumed without rewind or transparent reparse.
  priority: must
  stability: stable

- id: simd_json.stream_execution.binary_cursor_graph
  statement: A binary reduction shall create one unpublished padded input, parser, document, plan, and cursor graph at lazy setup, retain it across batches, and destroy it in dependency-safe order on every terminal path without chaining public open and close per batch.
  priority: must
  stability: stable

- id: simd_json.stream_execution.cursor_state_machine
  statement: A cursor shall move monotonically among ready, running, done, cancelled, and closed states with one running winner, idempotent terminal cleanup, and no parser access from invalid repeated transitions.
  priority: must
  stability: stable

- id: simd_json.stream_execution.single_in_flight_batch
  statement: One stream shall have at most one admitted native batch and one returned batch being consumed, and another batch shall not begin until every row in the current batch is consumed or reduction terminates.
  priority: must
  stability: stable

- id: simd_json.stream_execution.no_prefetch
  statement: Milestone 3 shall perform no multi-batch prefetch, and a paused or slow consumer shall cause no cursor advancement, new stream-specific native allocation, or stream-specific mailbox growth beyond the current batch.
  priority: must
  stability: stable

- id: simd_json.stream_execution.generation_and_retention
  statement: Setup and batch operations shall retain cursor, parent document, input, parser, plan, batch, private term environment, cancellation state, and coordinator metadata and validate generation before native dereference and delivery until terminal cleanup completes.
  priority: must
  stability: stable

- id: simd_json.stream_execution.early_halt_cleanup
  statement: Enum.take, Enum.find, reducer halt, consumer exception, and consumer death shall cancel in-flight work if needed, deterministically close the cursor, and release its native graph without parsing the unconsumed target-array or enclosing-document remainder.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.cancellation_boundaries
  statement: Streaming shall check cancellation before setup, target lookup, batch admission, each array element, bounded projection and conversion units, delivery, final validation, and done delivery while retaining resources across uninterruptible native work.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.close_shutdown_interlock
  statement: Document close, stream cleanup, garbage collection, application shutdown, and NIF unload shall prevent new work, cancel active batches, suppress stale delivery, drain admitted state, and release cursor and parent resources exactly once without unbounded normal-scheduler work.
  priority: must
  stability: stable

- id: simd_json.stream_execution.native_memory_baseline
  statement: Test builds shall prove input, parser, document, cursor, traversal-frame, plan, key-byte, row, slot, copied-string, batch, environment, operation, retained-resource, dispatcher, and failed-handoff gauges return to baseline after done, error, early halt, exception, caller death, close, garbage collection, and supported generation changes.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.scheduler_qualification
  statement: Large concurrent successful, failing, slow, halted, and cancelled streams shall preserve the accepted normal-scheduler heartbeat budgets with exact threaded setup and batch accounting and shall not use dirty schedulers as the stream queue.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.etl_benchmark
  statement: Streaming qualification shall compare complete SimdJson.stream/2 reduction with pinned Jason full decode, target lookup, equivalent row projection, and reduction using predeclared fixtures and shall report time to first row and batch, throughput, batch crossings, BEAM and native peak memory, retained input, garbage collection, scheduler latency, and early-halt cost.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.bounded_memory_acceptance
  statement: Before accepted measurements run, the repository shall declare and enforce reproducible thresholds showing working memory remains bounded across thousands of batches and materially below Jason full materialization for the qualified large-array ETL workload.
  priority: must
  stability: evolving

- id: simd_json.stream_execution.preproduction_boundary
  statement: Milestone 3 shall identify per-stream demand as local backpressure while continuing to label the Zigler-threaded runtime pre-production and shall not claim the bounded global queue, worker pool, cancellation registry, or public telemetry assigned to Milestone 4.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: simd_json.stream_execution.binary_lifecycle
  covers:
    - simd_json.stream_execution.lazy_setup
    - simd_json.stream_execution.threaded_stream_work
    - simd_json.stream_execution.binary_cursor_graph
    - simd_json.stream_execution.generation_and_retention
  given:
    - Valid, malformed, projection-failing, and allocation-failing large binary sources
  when:
    - Streams remain unreduced, fully reduce, fail after several batches, and are halted early
  then:
    - Unreduced streams create no native graph
    - One retained graph serves every batch of a reduction
    - Every terminal path releases that graph exactly once and copied rows remain independent

- id: simd_json.stream_execution.document_one_shot_and_close
  covers:
    - simd_json.stream_execution.owner_first_admission
    - simd_json.stream_execution.exclusive_document_cursor
    - simd_json.stream_execution.document_consumption
    - simd_json.stream_execution.close_shutdown_interlock
  given:
    - Fresh documents, selecting and streaming races, invalid options, rejected setup submission, active batches, and owner close
  when:
    - Owner and non-owner operations compete before and after cursor access
  then:
    - Owner checks precede state disclosure
    - Invalid and proven unstarted work leave the document fresh
    - One selection or stream commits the cursor and every post-access outcome leaves it consumed
    - Close waits for safe cursor cleanup and remains idempotent

- id: simd_json.stream_execution.slow_consumer_backpressure
  covers:
    - simd_json.stream_execution.correlated_batch_operations
    - simd_json.stream_execution.cursor_state_machine
    - simd_json.stream_execution.single_in_flight_batch
    - simd_json.stream_execution.no_prefetch
  given:
    - A multi-batch array and a consumer paused after selected rows in each returned batch
  when:
    - Native entries, cursor position, allocations, messages, and batch sequence are observed
  then:
    - At most one native batch and one returned batch exist
    - No next request or parser progress occurs during the pause
    - Each resumed request has the next exact sequence and one terminal result

- id: simd_json.stream_execution.early_halt_and_consumer_death
  covers:
    - simd_json.stream_execution.early_halt_cleanup
    - simd_json.stream_execution.cancellation_boundaries
    - simd_json.stream_execution.generation_and_retention
    - simd_json.stream_execution.native_memory_baseline
  given:
    - Binary and document streams paused at every setup, row, projection, conversion, and delivery boundary
  when:
    - A reducer halts, its callback raises, or its process exits
  then:
    - Work stops at the next safe boundary without an orphan batch
    - The remaining array is not scanned
    - Every retained native and private-term count returns to baseline exactly once

- id: simd_json.stream_execution.midstream_failure_recovery
  covers:
    - simd_json.stream_execution.correlated_batch_operations
    - simd_json.stream_execution.cursor_state_machine
    - simd_json.stream_execution.close_shutdown_interlock
    - simd_json.stream_execution.native_memory_baseline
  given:
    - Several delivered batches followed by malformed input, path/type/range failure, oversized row, allocation failure, cancellation, and stale delivery cases
  when:
    - Each failure reaches its containing batch
  then:
    - The failing batch is terminal and cannot advance again
    - Late or forged results complete no other request
    - Cursor, parent, batch, environment, and operation graphs return to baseline

- id: simd_json.stream_execution.concurrent_responsiveness
  covers:
    - simd_json.stream_execution.threaded_stream_work
    - simd_json.stream_execution.scheduler_qualification
    - simd_json.stream_execution.preproduction_boundary
  given:
    - Independent BEAM heartbeats and concurrent large successful, malformed, slow, early-halted, and cancelled streams
  when:
    - Qualification records normal and dirty scheduler utilization, worker entries, batch sequences, and memory peaks
  then:
    - Heartbeat latency remains inside the accepted budgets
    - Input-dependent work is observed only on the threaded path
    - Results prove local demand bounds without claiming a production global queue

- id: simd_json.stream_execution.jason_array_etl
  covers:
    - simd_json.stream_execution.etl_benchmark
    - simd_json.stream_execution.bounded_memory_acceptance
  given:
    - Predeclared small, medium, and million-row sparse array fixtures, equivalent row projections and reductions, a batch-size matrix, slow and early-halt consumers, environment, samples, and memory thresholds
  when:
    - SimdJson.stream/2 is compared end to end with Jason decode, lookup, projection, and Enum reduction
  then:
    - The report contains every required latency, throughput, crossing, scheduler, garbage-collection, retained-input, and memory dimension
    - Memory remains bounded across thousands of batches and the declared large-fixture advantage passes without excluding setup, reduction, or cleanup costs
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed lazy setup,
threaded correlation, owner-first admission, select/stream exclusion, document
consumption, binary lifetime, cursor state, slow-consumer, no-prefetch,
early-halt, consumer exception/death, cancellation, close, shutdown, sanitizer,
baseline, scheduler, and frozen end-to-end Jason ETL evidence.

## Verification

```spec-verification
- kind: command
  target: bash scripts/ci/qualify_stream_execution.sh
  execute: true
  covers:
    - simd_json.stream_execution.lazy_setup
    - simd_json.stream_execution.threaded_stream_work
    - simd_json.stream_execution.correlated_batch_operations
    - simd_json.stream_execution.owner_first_admission
    - simd_json.stream_execution.exclusive_document_cursor
    - simd_json.stream_execution.document_consumption
    - simd_json.stream_execution.binary_cursor_graph
    - simd_json.stream_execution.cursor_state_machine
    - simd_json.stream_execution.single_in_flight_batch
    - simd_json.stream_execution.no_prefetch
    - simd_json.stream_execution.generation_and_retention
    - simd_json.stream_execution.early_halt_cleanup
    - simd_json.stream_execution.cancellation_boundaries
    - simd_json.stream_execution.close_shutdown_interlock
    - simd_json.stream_execution.native_memory_baseline
    - simd_json.stream_execution.scheduler_qualification
    - simd_json.stream_execution.etl_benchmark
    - simd_json.stream_execution.bounded_memory_acceptance
    - simd_json.stream_execution.preproduction_boundary
    - simd_json.stream_execution.binary_lifecycle
    - simd_json.stream_execution.document_one_shot_and_close
    - simd_json.stream_execution.slow_consumer_backpressure
    - simd_json.stream_execution.early_halt_and_consumer_death
    - simd_json.stream_execution.midstream_failure_recovery
    - simd_json.stream_execution.concurrent_responsiveness
    - simd_json.stream_execution.jason_array_etl
```
