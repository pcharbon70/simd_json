---
id: simd_json.document_resource_and_buffer_ownership
status: accepted
date: 2026-08-27
affects:
  - simd_json.document_resource
  - simd_json.document_api
---

# Document Resource and Input Buffer Ownership

## Context

simdjson's On-Demand document and cursor state reference the original JSON bytes. Those bytes must remain valid, correctly padded, and unchanged for the complete native lifetime. An ordinary BEAM binary does not guarantee the extra readable padding required by simdjson's fastest APIs, and a raw native pointer stored outside a BEAM resource would permit use-after-free.

The On-Demand API is also stateful and forward-moving. A mutex can prevent memory corruption, but it cannot turn one cursor into a sensible concurrently shared immutable tree. Milestone 1 must establish ownership and lifecycle semantics that later projection and streaming work can extend without changing the foundation.

## Decision

### Opaque resource graph

`SimdJson.Document` wraps an opaque BEAM resource. It never exposes a native address, C handle, parser pointer, buffer pointer, or cursor generation through public fields or inspection.

The native document resource owns:

- one padded input buffer;
- one simdjson parser handle;
- one On-Demand document handle;
- the owning BEAM PID;
- an atomic lifecycle state;
- a monotonically changing generation used to reject stale child resources;
- only the synchronization needed for bounded lifecycle transitions.

Future cursor resources retain the parent document resource through the BEAM resource API. Copying a raw parent pointer without retaining the resource is forbidden.

### Input strategy

Milestone 1 always copies the input binary once into an aligned native buffer with the exact padding required by the pinned simdjson release. Required padding bytes are initialized according to that release's contract.

Zero-copy input is disabled. It may be proposed later only with a separate accepted decision and evidence covering the exact simdjson entry point, BEAM allocation behavior, alignment, padding, guard pages, binary lifetime, sub-binaries, and every supported runtime target.

The logical JSON length remains distinct from allocated capacity and padding. Native parsing and error offsets use the logical length; no padding byte may appear as input or output.

### Ownership and lifecycle

The process that successfully calls `SimdJson.open/1` owns the document. Calls from another process return `{:error, %SimdJson.Error{reason: :not_owner}}`; possession of the Elixir term does not transfer ownership. Ownership is checked before lifecycle details are disclosed. Milestone 1 provides no ownership-transfer API.

The resource lifecycle is:

```text
open → closing → closed
```

Only one transition from `open` to `closing` wins. Explicit `close/1`, garbage collection, partial-open failure, caller termination, and NIF unload converge on the same exactly-once cleanup protocol.

`close/1` is idempotent for the owner. The first owner close waits outside a normal scheduler until the shared cleanup operation reaches `closed` and all document-owned native allocations have been released. An owner close that encounters `closing` joins that completion; an owner close that encounters `closed` returns `:ok` immediately. Thus every successful owner close returns `:ok` only when deterministic release is complete. Every other owner document operation after close returns `{:error, %SimdJson.Error{reason: :closed}}`.

A garbage-collection callback cannot wait. It may atomically detach and enqueue the same cleanup operation, then return; the retained resource metadata remains alive until that cleanup reaches `closed`.

Destruction occurs in this order:

1. prevent new work and invalidate the active generation;
2. wait for or transfer ownership from any admitted native operation without blocking a normal scheduler;
3. destroy the On-Demand document;
4. destroy the parser;
5. release the padded input buffer;
6. mark cleanup complete and release remaining resource metadata.

The resource destructor is a safety net, not a second cleanup implementation. Large or otherwise unbounded teardown is deferred to the accepted off-scheduler cleanup path.

### Phase 3 implementation checkpoint

Phase 3 realizes the decision below the public API. Zig imports the canonical C
header, owns one 64-byte-aligned input copy with the pinned 64 initialized
padding bytes, registers the opaque resource, and implements admission,
generation invalidation, reverse rollback, and exactly-once cleanup guards.
Ordinary and sanitizer native tests cover source-buffer independence, guard
pages, every construction edge, concurrent close, parent-retention accounting,
and quiescence without exposing pointers or JSON.

This checkpoint does not alter the decision or make parsed resources
production-reachable. The BEAM fixture contains only destructible empty state;
threaded construction and deferred cleanup arrive in Phase 4, while owner
enforcement and public idempotent close arrive in Phase 5.

### Phase 5 public-boundary checkpoint

`SimdJson.Document` now wraps the registered resource behind an opaque type and
redacted inspection. Before public cleanup admission, one bounded synchronous
NIF entry verifies the registered resource type and compares the calling PID
with immutable owner metadata. That comparison occurs before lifecycle is read,
so another process receives `not_owner` for both open and closed documents and
cannot mutate lifecycle or enqueue cleanup. A forged struct containing an
ordinary reference or another resource type fails the native type decoder.

An accepted owner delegates close to the correlated threaded cleanup path.
Closed resources return immediately, while open or closing resources share the
existing exactly-once cleanup owner. The wrapper exports no raw resource
accessor, ownership transfer, cursor, serialization, or document operation
beyond close. This checkpoint implements the existing decision without changing
the single-owner or lifecycle model.

### Phase 6 lifecycle-qualification checkpoint

The final bounded stress profile randomizes caller death across all five native
cancellation boundaries, injects parse, explicit-cleanup, and callback-handoff
submission rejection, mixes owner/repeated/non-owner close with dropped terms
and forced GC, and cycles supported application generations. Each batch waits
for bounded quiescence and compares every BEAM-exposed live native gauge with
its recorded baseline. The mixed batch also requires exactly one completed
document cleanup for every successfully opened document.

The standalone Zig ordinary and sanitizer profiles remain the authority for
per-buffer, parser/document-handle, resource-record, retained-parent, and
reverse-destruction accounting. The combined evidence therefore proves the
complete graph without adding a public pointer, content, or counter surface.

### Milestone 2 Phase 4 projection checkpoint

The resource now carries a projection state independent of its monotonic
lifecycle: `fresh -> selecting -> consumed`. A bounded owner-first admission
reserves the single cursor, captures the document generation, and holds an
admitted-operation interlock. A proven pre-worker rejection can roll that
reservation back to `fresh`; once the worker claims cursor access, every
terminal outcome remains `consumed`. Close first prevents new reservations,
cancels matching projection operations through the stable coordinator, and
waits on the existing threaded cleanup path until the committed reservation is
released.

Document projection retains the resource control, parser, document, and padded
input through traversal, copied-string construction, join, and terminal
discard. Binary projection uses the same ownership implementation in an
unpublished temporary document graph wholly owned by its worker. The Phase 4
integration matrix destroys source documents and drops caller input before
reusing returned strings, kills binary and document callers at every defined
projection boundary, and restores all live document and projection gauges to
baseline. The root API still exposes no projection operation until Milestone 2
Phase 5.

### Milestone 2 Phase 5 and 6 public-lifetime checkpoints

The root API now exposes `select/2` without exposing the document resource,
cursor, reservation, generation, or native identity. Its bounded genuine
resource and owner check precedes reservation; invalid projection and proven
pre-worker rejection leave the document fresh, while cursor access commits the
decided one-shot state.

The final seeded profile covers binary and document caller death at all six
projection boundaries, every reachable injected failure checkpoint,
submission rollback and retry, owner/non-owner calls, repeated close, dropped
results and documents, forced GC, callback-handoff retry, and application
generation changes. Each bounded batch returns all exposed document,
operation, retained-source, plan, slot, private-environment, temporary-graph,
dispatcher, and failed-handoff gauges to baseline. Standalone sanitizer
accounting remains the authority for parser handles, plan nodes, and copied key
bytes. This evidence activates projection without changing single ownership or
permitting document reuse after cursor access.

## Consequences

Milestone 3 Phase 2 implementation checkpoint: the private stream cursor
resource keeps a genuine parent document before any borrowed native document
can be used, and destroys cursor/plan state before releasing that parent.
Rollback, non-owner rejection, genuine resource retention, and ordinary/
sanitizer lifetime accounting are covered by executable tests.

The input remains valid for the complete parser lifetime and zero-copy ambiguity cannot cause an over-read. Explicit close releases large native allocations deterministically, while garbage collection safely handles abandoned documents.

The initial implementation always pays one input copy and cannot share a document across processes. That cost is accepted because it is bounded by input size and still avoids full BEAM-tree materialization in later milestones.

Later cursors and streams inherit a stable parent-retention and generation model. They cannot weaken owner or lifetime guarantees without superseding this decision.

## Alternatives Rejected

- **Assume every BEAM binary has simdjson padding:** the BEAM makes no such general promise.
- **Return sub-binaries or raw native views as document state:** this exposes lifetime coupling and can retain unexpectedly large inputs.
- **Store parser pointers in a plain Elixir struct:** garbage collection cannot enforce the native ownership graph.
- **Permit concurrent cursor access under a mutex:** serialization prevents races but does not make forward-only cursor semantics coherent.
- **Make garbage collection the only close mechanism:** callers need deterministic release for large native allocations.
- **Free large native state directly in an ordinary resource destructor:** teardown latency would become an uncontrolled scheduler cost.

## Reopening Conditions

Zero-copy input, ownership transfer, or shared document use requires a new accepted decision with platform-specific safety evidence and unchanged use-after-free guarantees. The cleanup order may change only if the pinned simdjson ownership contract changes and native sanitizer plus scheduler evidence proves the replacement.
