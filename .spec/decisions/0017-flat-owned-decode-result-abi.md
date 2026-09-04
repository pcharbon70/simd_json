---
id: simd_json.flat_owned_decode_result_abi
status: accepted
date: 2026-09-04
affects:
  - simd_json.decode_api
  - simd_json.native_build_and_abi
---

# Flat Owned Decode Result ABI

## Context

Decode must cross the C++/Zig boundary without exporting C++ containers,
retaining pointers into the input, publishing a partial tree, or recursively
walking attacker-controlled nesting. A pointer-linked tree would complicate
rollback and make ABI validation depend on allocation topology.

## Decision

ABI v4 introduces opaque materializer and result owners. A successful result
exposes one immutable borrowed view containing flat node and edge arrays plus
result-owned copied bytes. Nodes and edges refer to one another by checked
64-bit indices; no internal native pointer crosses the ABI. Object edges name
copied key ranges, while array edges use the unavailable-byte-range sentinel.

The materializer owns an explicit bounded frame vector. Execution builds into
private temporary storage and transfers a result handle only after the complete
graph is valid. Destruction accepts null, result views expire when their owner
is destroyed, and every constructor or execution failure leaves its output
null. No BEAM term enters this phase.

## Consequences

Phase 3 can add value traversal without changing ownership or layout. Zig can
validate and convert the graph iteratively, and cancellation or allocation
failure has one deterministic rollback path. The flat graph uses indices and
some temporary native memory in exchange for auditable ownership.
