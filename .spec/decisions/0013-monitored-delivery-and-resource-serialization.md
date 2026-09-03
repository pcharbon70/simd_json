---
id: simd_json.monitored_delivery_and_resource_serialization
status: accepted
date: 2026-09-03
affects:
  - simd_json.native_pool
  - simd_json.native_execution
  - simd_json.document_api
  - simd_json.document_resource
  - simd_json.projection_api
  - simd_json.projection_execution
  - simd_json.stream_execution
  - simd_json.package
---

# Monitored Delivery and Resource Serialization

## Context

Owned FIFO jobs need a terminal protocol before public operations can use the
pool. Caller death, explicit cancellation, shutdown, result delivery, and close
can race, while a stateful document or cursor must never have two conflicting
operations in flight.

## Decision

Each cancellable pool job retains a native request resource with the caller
PID, an ERTS process monitor, a unique request reference, an independently
allocated message environment, an atomic cancellation flag, and one terminal
state. The resource down callback requests cancellation without allocation.
Workers demonitor at the terminal boundary and select exactly one of cancelled,
delivered, or discarded. A failed send to a dead caller is ordinary discarded
cleanup.

Stateful jobs also retain a resource reservation. Admission atomically changes
ready to reserved; overlap is rejected. Close changes ready directly to closed
or reserved to closing, blocks new admission, and lets the final job perform
the sole closing-to-closed transition. Independent resources remain concurrent.

Shutdown requests cooperative cancellation before workers drain and join.
Workers check before execution, every bounded fixture chunk, and before result
delivery. Phase 4 exposes these mechanisms only through test-only fixtures;
public open, select, and stream routing remains unchanged and the executor stays
`:preproduction_threaded` until Phase 5.

## Consequences

Cancellation/completion races have a single terminal owner, cross-thread terms
belong to a valid environment, and resource close cannot overlap conflicting
state advancement. Production routing and telemetry still require the next
phase and cannot be inferred from the fixture evidence.
