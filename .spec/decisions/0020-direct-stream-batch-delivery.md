---
id: simd_json.direct_stream_batch_delivery
status: accepted
date: 2026-10-02
affects:
  - simd_json.stream_execution
  - simd_json.native_pool
  - simd_json.native_execution
  - simd_json.package
---

# Direct Stream Batch Delivery

## Context

The production stream path constructed each bounded list of row maps in the
operation environment, copied it into the pool job environment, sent it to the
operation coordinator, and then caused the BEAM to copy it again into the
consumer mailbox. On a one-million-row reduction, native parsing and projection
were a minority of total elapsed time; repeated copying and routing of already
materialized BEAM terms dominated the remaining work.

The coordinator must continue to own admission, caller monitoring,
cancellation, operation completion, and telemetry lifecycle. Removing it from
those responsibilities would weaken the fixed-pool and exactly-once cleanup
contracts.

## Decision

Production next-batch jobs construct the complete transactional batch in the
pool job environment that will deliver it. The pool sends that bounded result
directly to the monitored stream owner. It separately sends the coordinator a
small terminal notice containing only request correlation, delivery outcome,
and queue/execution timings. The coordinator uses that notice to finish the
operation and release its request graph; it never receives or forwards the row
list.

The delivery environment and the terminal-notice environment are distinct.
Each `enif_send` may consume or clear its message environment, so neither
environment may be reused for a second message or retained term. Legacy
qualification seams may still copy from an operation-owned environment, but
the public production stream uses the single-copy delivery path.

Queue and execution durations use a monotonic POSIX clock inside native worker
threads and are converted from microseconds at the Elixir telemetry boundary.
Caller-side correlation and response normalization are measured separately as
conversion duration.

All prior stream constraints remain: one admitted batch per cursor, no
prefetch, exact source order, bounded row and byte limits, owner monitoring,
generation and sequence validation, transactional errors, prompt cancellation,
and deterministic cleanup.

## Consequences

Each public batch crosses from the native pool to its consumer once instead of
passing through the coordinator. Coordinator mailbox growth is independent of
row count and selected-value size. The public stream and row-map API does not
change.

The native request control now distinguishes a result recipient from a
lifecycle observer. Qualification must cover successful direct delivery,
caller death, cancellation, quiescence, nonzero native execution timing, and
the full one-million-row reduction.

The precompiled NIF must be rebuilt and requalified before release because the
private binding set and native implementation changed.

## Alternatives Rejected

- **Keep forwarding through the coordinator:** this preserves simple routing
  but copies every materialized batch through an unnecessary BEAM process.
- **Encode a second compact binary wire format:** local measurement showed that
  decoding and rebuilding every row map in Elixir cost more than the avoided
  native term construction and mailbox copying.
- **Send no completion notice:** the consumer would receive rows, but the
  coordinator could not deterministically retire monitoring and operation
  state.
- **Reuse one NIF environment for both sends:** `enif_send` may clear the
  environment and corrupt the second message.

## Reopening Conditions

Revisit this decision if OTP introduces a verified zero-copy process-forwarding
primitive, if a different public batch representation is accepted, or if
controlled million-row evidence shows direct delivery regresses lifecycle,
memory, or throughput. Any replacement must preserve bounded batches,
exactly-once terminal ownership, cancellation, and redacted telemetry.
