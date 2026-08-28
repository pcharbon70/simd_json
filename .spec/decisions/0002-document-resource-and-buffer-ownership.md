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

## Consequences

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
