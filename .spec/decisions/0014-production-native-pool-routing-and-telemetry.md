---
id: simd_json.production_native_pool_routing_and_telemetry
status: accepted
date: 2026-09-04
affects:
  - simd_json.native_pool
  - simd_json.native_execution
  - simd_json.document_api
  - simd_json.document_resource
  - simd_json.projection_api
  - simd_json.projection_execution
  - simd_json.stream_cursor
  - simd_json.stream_execution
  - simd_json.streaming_api
  - simd_json.package
  - simd_json.native_build_and_abi
---

# Production Native Pool Routing and Telemetry

## Context

Phase 4 proved bounded workers, owned jobs, cancellation, delivery, and
serialization with fixtures. Public operations still used the provisional
Zigler threaded launcher, so configured queue capacity did not govern
application work.

## Decision

Public document open and cleanup, binary and document projection, stream
setup, and every next-batch demand are typed jobs on the one fixed native
pool. Jobs retain operation and stateful resources and copy setup terms into
owned environments before submit returns. Fixed workers install independent
NIF environments, execute the existing native implementations, and send one
correlated result. Saturation returns immediately without fallback work.

Native completions carry only bounded queue and execution durations. The
coordinator emits telemetry from BEAM with finite operation/outcome metadata
and duration, byte, row, and capacity measurements. Content, paths, selected
values, PIDs, addresses, and references are forbidden.

Application shutdown drains requests before joining workers; NIF unload also
stops and joins the pool. In-place upgrade is rejected while an old runtime or
pool exists, requiring an application restart before native replacement.

## Consequences

Diagnostics now identify `:bounded_native_pool`, and configured capacity
governs public native work. Phase 6 still owns saturation, latency, fairness,
memory, sanitizer qualification, operations guidance, and subject activation.
