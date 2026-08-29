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
