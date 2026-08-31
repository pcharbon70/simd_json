---
id: simd_json.projection_admission_consumption_and_lifetime
status: accepted
date: 2026-08-29
affects:
  - simd_json.projection_execution
  - simd_json.projection_api
  - simd_json.document_resource
  - simd_json.native_execution
---

# Projection Admission, Consumption, and Lifetime

## Context

Milestone 1 documents contain a single-owner, stateful On-Demand cursor and a
correlated Zigler-threaded qualification runtime. Projection must reuse those
resources without pretending the document is an immutable tree. The contract
must say exactly when an attempted projection consumes cursor state, how close
interacts with active work, and when temporary binary-source allocations are
released.

Without one explicit rule, a failed lookup might leave a document reusable on
one path but consumed on another, or a caller could receive a string that still
borrows input already destroyed by automatic cleanup.

## Decision

### Off-scheduler operation boundary

Projection compilation, On-Demand traversal, result-slot processing, and any
input-dependent cleanup run through the accepted correlated Zigler-threaded
path. They never run as ordinary NIF work and never fall back to dirty CPU
schedulers. Ordinary entry work is limited to argument/resource checks,
bounded state transitions, retention, correlation, and submission.

One public `select/2` call creates one correlated native operation and returns
one terminal result. Internal C calls and chunked conversion do not create
additional BEAM/NIF request crossings.

The Milestone 1 runtime remains a qualification mechanism. Milestone 2 does not
claim the bounded production worker pool, admission queue, backpressure, or
public telemetry assigned to Milestone 4.

### Document selection state

The document lifecycle remains `open -> closing -> closed`. A separate
single-use projection state is added:

```text
fresh -> selecting -> consumed
```

Only the document owner may reserve `fresh -> selecting`. Reservation checks
owner first, then lifecycle and generation, and admits at most one projection.
A second owner selection sees `:cursor_consumed` once selection has been
reserved or completed; another process always sees `:not_owner` before cursor
or lifecycle detail is disclosed.

Invalid source terms, projection preflight failures, non-owner calls, closed
documents, and native submission rejection before worker admission do not
consume the document. A failed submission rolls a private reservation back to
`fresh` only after proving no worker can observe it.

Once a worker crosses its first cursor-access boundary, the operation commits
the document to `consumed`. Success, missing paths, type errors, malformed JSON,
numeric range errors, cancellation, caller death, and internal failures after
that boundary all end in `consumed`. Milestone 2 never rewinds or silently
reparses a document.

The generation captured at reservation is checked before every native
dereference and before delivery. Operation resources retain the document and
its input until traversal, conversion, discard, and terminal cleanup finish.

### Phase 1 pre-admission checkpoint

Phase 1 stops deliberately before projection reservation. A private test seam
accepts a binary or genuine open document term but sends only the projection to
the BEAM validator, making source independence observable before `select/2`
exists. Test builds count every attempted entry through the existing
`ThreadedOperation.admit/3` boundary. Invalid and valid preflight both leave
those counters, the coordinator request set, native allocation gauges, worker
entries, module generation, and the existing document lifecycle unchanged.

The `fresh -> selecting -> consumed` state and the projection operation kind do
not exist at this checkpoint. They remain later implementation work; this
evidence establishes only the decision's pre-admission non-consumption side and
does not claim that document selection or rollback is implemented.

### Phase 3 native-execution checkpoint

The standalone ABI engine now checks cancellation before its first cursor
claim and between bounded traversal units. A cancellation before that claim
leaves the opaque native document eligible for execution; after the atomic
claim, success and every failure make a second native execution return
`cursor_consumed`. This defensive native rule is exercised only in C/Zig
harnesses and does not yet implement the owner-first `fresh -> selecting ->
consumed` resource state, threaded reservation rollback, close interlock, or
public lifecycle behavior assigned to Phase 4.

### Phase 4 internal runtime checkpoint

The private runtime now implements the complete admission and lifetime model.
A genuine document resource is checked owner-first, reserves one atomic
projection generation, retains its control graph in one correlated operation,
and moves from `fresh` to `selecting`. Invalid preflight and lifecycle or owner
rejection create no reservation. Injected submission rejection proves that no
worker can observe the operation before rolling `selecting` back to `fresh`.
Immediately before the first native cursor handle is obtained, the worker
commits the reservation; success, path/type/range/allocation failure,
cancellation, caller death, close, and shutdown then all release it as
`consumed`.

Binary selection creates its padded input, parser, unpublished document, plan,
slots, and private result environment inside the same worker and destroys the
temporary native graph before completion delivery. Document selection retains
the existing resource until copied strings and the complete result map have
crossed the generated join. Close cancels every matching active reservation and
waits for terminal release before reverse destruction. Generation checks guard
admission, document dereference, and delivery.

Deterministic integration controls pause all six cancellation boundaries. The
Phase 4 matrices force binary and document results to complete out of order,
kill callers at each boundary, race selecting documents with close and
application shutdown, reject and retry GC cleanup handoff, force conversion
allocation failures, and compare every live projection/document gauge with its
baseline. This checkpoint remains an undocumented internal seam; Phase 5 owns
the public `SimdJson.select/2` contract and error translation.

### Phase 5 public admission checkpoint

The public wrapper preserves the Phase 1 order by completing projection
preflight before source parsing or document reservation. A bounded document
resource/owner/lifecycle check rejects forged resources, non-owners, and closed
documents without creating a projection request. A fresh owner document and a
binary then enter the same Phase 4 correlated operation with no public options
or synchronous fallback. Submission rejection remains retryable, while any
attempt that crosses cursor access remains consumed and owner close remains
idempotent.

Public tests cover invalid and forged sources with zero projection admission,
invalid projections with an unchanged fresh document, binary temporary-graph
cleanup, exact copied result lifetime, owner-first fresh/consumed/closed
behavior, submission rollback, and all gauges at baseline. The threaded layer
remains explicitly pre-production; no public cancellation control, diagnostic,
worker-pool, backpressure, rewind, reparse, or reusable-plan behavior is added.

### Close, cancellation, and shutdown

Close or shutdown prevents new projection admission. If selection is active,
the close path requests cancellation, waits off scheduler for the operation to
reach a safe terminal boundary, suppresses stale delivery, and then follows the
existing exactly-once document destruction order. A resource callback may only
perform the existing bounded detach/handoff behavior.

Cancellation is checked before plan compilation, before cursor access, between
bounded traversal units, before term construction, between bounded conversion
chunks, and before delivery. An uninterruptible simdjson call retains every
resource until its next safe boundary.

### Binary-source lifetime

`select(binary, projection)` is one temporary-document operation. After
projection preflight succeeds, the worker creates the required owned padded
copy, parser, document, plan, and result slots; traverses and converts; and
destroys all native state before delivering either success or failure. It does
not call the public `open/1` and `close/1` pair or publish a temporary document.

Every returned term, including every selected string, is independent of the
temporary document before the call returns. Allocation failure, cancellation,
caller death, malformed input, and result-conversion failure release the same
graph exactly once.

### Qualification

Milestone 2 preserves the Milestone 1 scheduler and lifecycle budgets under
large concurrent successful and failing projections. Native counters and
sanitizers must return document, plan, slot, environment, operation, and
retained-resource allocations to baseline after document-source and
binary-source success, failure, cancellation, caller death, close, GC, and
application-generation transitions.

The sparse-projection benchmark is end to end. It includes validation, plan
compilation, structural scanning, traversal, term construction, scheduling,
and cleanup, and compares against Jason full decode plus equivalent lookups.
Parser-kernel-only results cannot qualify the milestone. Allocation acceptance
thresholds and fixtures are declared before final measurements are recorded.

### Phase 6 qualification checkpoint

The final profile executes successful, malformed, missing, wrong-type, and
cancelled 4 MiB projections beside a 2 ms heartbeat and records raw
nearest-rank percentiles plus normal, dirty CPU, and dirty I/O scheduler
utilization. A seeded matrix covers all six cancellation boundaries for binary
and document sources, every reachable injected allocation checkpoint,
retryable submission, owner and close behavior, dropped terms, GC handoff
retry, and application generation changes. Each batch reaches bounded native
quiescence. Application restart remains the supported generation boundary and
is not presented as evidence of repeated in-process shared-object unload.

## Consequences

Document-source behavior is deterministic: a document is a one-shot projection
cursor, while `close/1` remains idempotent after consumption. Callers who need
another projection open another document or use the binary form again.

The binary form avoids exposing temporary native lifetime and guarantees that a
successful result owns everything it needs. It may repeat input copying for
repeated calls; public compiled plans, reparsing, or reusable immutable document
views remain future optimizations.

Projection inherits the pre-production concurrency limitations of Milestone 1.
The additional qualification proves scheduler safety but does not substitute
for the Milestone 4 worker pool.

## Alternatives Rejected

- **Reuse a document after successful traversal:** On-Demand state is
  forward-only and transparent rewind would hide reparsing cost.
- **Reuse only after selected failures:** cursor position varies by failure,
  producing error-dependent and order-dependent semantics.
- **Consume on projection grammar errors:** validation does not touch the JSON
  cursor and should be safe to correct and retry.
- **Implement the binary form as public open/select/close calls:** that creates
  multiple operation boundaries and exposes partial lifetime between them.
- **Let close destroy active projection state immediately:** the worker could
  dereference freed parser, plan, input, or result storage.
- **Move projection to dirty CPU schedulers:** this would turn a VM-wide limited
  facility into the library's JSON queue.

## Reopening Conditions

Reusable documents, rewind/reparse behavior, ownership transfer, shared
documents, a public compiled plan, or the Milestone 4 worker pool require a new
or superseding decision. Any change must preserve owner-first checks,
generation safety, exactly-once cleanup, cancellation-safe retention, and
explicit cost semantics.
