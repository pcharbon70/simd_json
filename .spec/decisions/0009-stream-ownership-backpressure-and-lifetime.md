---
id: simd_json.stream_ownership_backpressure_and_lifetime
status: accepted
date: 2026-08-31
affects:
  - simd_json.stream_execution
  - simd_json.stream_cursor
  - simd_json.streaming_api
  - simd_json.document_resource
  - simd_json.native_execution
---

# Stream Ownership, Backpressure, and Lifetime

## Context

A lazy stream divides one forward-only parse across many reductions and native
operations. The source, document, cursor, projection plan, current batch, and
operation state must remain valid across idle consumer time without allowing a
second process or request to advance the same iterator. Early halt and consumer
failure must release that retained graph without scanning millions of remaining
rows.

Milestone 4 owns the final fixed worker pool, bounded global queue,
caller-monitoring registry, admission backpressure, and public telemetry.
Milestone 3 still needs per-stream demand control and cancellation-safe cleanup
while it continues to use the accepted pre-production Zigler-threaded runtime.

## Decision

### Stream and cursor ownership

`SimdJson.stream/2` records the constructing PID. Reduction start, cursor
creation, every batch request, and cleanup validate that owner before exposing
lifecycle or generation state. Passing the stream or any internal resource term
to another process does not transfer ownership and raises a `SimdJson.Error`
with reason `:not_owner` during reduction.

The public stream term contains no public cursor handle. During reduction, one
private cursor resource retains its genuine parent document resource through
the BEAM resource API. The parent document continues to own its parser and
padded input. Batch operations retain the cursor, parent document, plan,
private environment, cancellation state, and request metadata until delivery
or terminal discard completes.

The cursor state is monotonic:

```text
ready -> running -> ready
  |         |        |
  |         +------> cancelled -> closed
  +----------------> done ------> closed
  +----------------> closed
```

Only one transition to `running` can win. `next_batch` on `running`, cancelled,
or closed state never touches the parser. Terminal error cancels and closes the
cursor after cleanup; normal completion moves through `done` and deterministic
close.

### Document and binary source graphs

For a binary source, reduction start creates one unpublished owned padded
input, parser, document, compiled row projection, and cursor through the
off-scheduler path. That graph lives across batches and is destroyed in reverse
dependency order on done, error, early halt, consumer death, callback failure,
application shutdown, or garbage collection. The public `open/1` and `close/1`
operations are not chained around each batch.

For a document source, stream admission participates in the existing one-shot
cursor reservation. The generalized state admits exactly one of projection or
streaming:

```text
          -> selecting -
fresh ---<              >--- consumed
          -> streaming -
```

Owner, lifecycle, and generation are checked before reservation. Invalid
stream options, a non-owner call, a closed resource, and a proven submission
rejection before any worker can observe the reservation leave the document
fresh. Immediately before target-path cursor access, streaming commits the
reservation. Success, target or row failure, cancellation, early halt, consumer
exception, caller death, close, shutdown, or internal failure after that point
all leave the document consumed. No path rewinds or reparses it.

The stream cursor retains the parent resource after commitment. Document close
prevents new stream work, requests cancellation of an active cursor, waits off
scheduler for its admitted batch and cursor cleanup to become safe, and then
continues the existing exactly-once document destruction order. Generation is
checked before every native dereference and before each batch delivery.

### Demand-driven batch operations

Cursor setup is one uniquely correlated threaded operation. Each call for the
next batch is another uniquely correlated operation with exactly one terminal
bounded batch or error. There is never a NIF call per row, field, segment, or
yielded map.

At most one native batch operation is admitted for a cursor. After delivery,
the Elixir enumerable holds at most that one returned batch and yields all of
its rows before asking for another. Milestone 3 performs no multi-batch
prefetch. An idle or slow consumer therefore causes no parser advancement,
native batch allocation, or stream-specific message growth beyond the current
batch.

This per-stream demand contract is backpressure but not the Milestone 4 global
admission design. The provisional runtime may still have weaker system-wide
capacity control. Documentation and benchmarks must keep that distinction
explicit and must not claim a bounded production queue or production telemetry.

Late, duplicate, stale, mismatched, cancelled, timed-out, or orphaned setup and
batch results are discarded only after their complete native and private-term
graphs are released. Correlation includes operation kind, unforgeable request
reference, cursor generation, and batch sequence so a response can never
complete a different cursor or batch.

### Early halt, consumer failure, and cancellation

Normal enumerable termination, `Enum.take/2`, `Enum.find/2`, reducer halt,
consumer exception, and explicit process exit all converge on the same cursor
close protocol. Cleanup marks cancellation, prevents another batch, cancels any
in-flight operation, waits for or safely transfers it at the accepted native
boundary, destroys the current cursor graph, and returns or reraises only after
deterministic cleanup is established.

An early halt does not advance, validate, or materialize the unconsumed portion
of the target array or enclosing document. This is intentional lazy behavior,
not successful complete-source validation. Rows in already delivered batches
remain ordinary independent BEAM terms.

Cancellation is checked:

- before cursor setup and target lookup;
- before each batch submission and native batch start;
- between array elements and bounded projection traversal units;
- before and during chunked row/batch BEAM conversion;
- before batch delivery;
- before final document validation and done delivery.

Resource callbacks remain bounded. They detach or hand off cursor/document
cleanup to the existing cleanup-only dispatcher and never parse remaining
input, wait for a worker, launch Zigler work from callback context, or destroy
unbounded state on a normal scheduler. Failed handoff retains exactly one
cleanup owner for retry.

### Qualification

Milestone 3 qualification must prove:

- zero native progress while a stream is constructed but unreduced or while a
  consumer is paused between batches;
- one setup operation, one plan construction, and exactly one batch operation
  per delivered native batch;
- no more than one in-flight and one returned batch per stream;
- row-count and encoded-byte limits under small values, huge strings, exact
  boundaries, allocation failure, and cancellation;
- parent/document/cursor/plan/batch/environment gauges return to baseline after
  done, error, early halt, consumer exception/death, close, GC, and supported
  application-generation changes;
- large concurrent stream consumers preserve the accepted scheduler heartbeat
  budgets and do not use dirty schedulers as the JSON queue.

The end-to-end ETL benchmark compares `SimdJson.stream/2` with pinned Jason full
decode plus equivalent array lookup, row projection, and reduction. It includes
option validation, input copy, target lookup, plan compilation, every batch
crossing, term construction, consumer reduction, cleanup, latency to first row
and batch, total throughput, BEAM/native peak memory, retained input, garbage
collection, scheduler utilization, and early-halt behavior. Fixtures, batch
matrix, consumer work, and acceptance thresholds are committed before accepted
measurements.

## Consequences

Native progress is controlled directly by consumer demand, and early halt can
release a huge parse without scanning the remainder. A cursor can remain idle
while retaining a large input, so abandoned-stream cleanup and deterministic
enumerable finalization are correctness requirements.

Each batch is a separate correlated operation. This adds one boundary per batch
but creates cancellation, fairness, allocation, and backpressure points that a
single whole-array operation would lack.

Document-backed streams are one-shot even when halted early or failed after
cursor access. Binary-backed streams can be rebuilt by a later reduction at the
explicit cost of another input copy and parse.

## Alternatives Rejected

- **Prefetch the next batch:** it weakens cancellation and slow-consumer memory
  bounds before measurements justify the complexity.
- **Allow concurrent `next_batch` calls:** a mutex would prevent memory races
  but not provide coherent forward-only ordering or error semantics.
- **Leave an early-halted cursor for garbage collection:** large native input
  needs deterministic release through normal enumerable cleanup.
- **Finish parsing after early halt:** it spends CPU on data the caller no
  longer demands and defeats lazy cancellation.
- **Return one native operation for the entire array:** output memory and time
  to cancellation would scale with total records.
- **Claim the provisional threaded coordinator is production backpressure:**
  per-stream demand does not bound aggregate admission across callers.
- **Roll a document back to fresh after cursor access:** iterator position is
  already changed and transparent reparse would hide cost.

## Reopening Conditions

Milestone 4 will supersede the provisional scheduling portions when it accepts
the fixed worker pool, bounded global admission, process cancellation registry,
telemetry, and shutdown protocol. Prefetch, cursor transfer, checkpoint/resume,
or shared cursor access requires a separate decision with equally strict
memory, ordering, cancellation, and lifetime evidence.
