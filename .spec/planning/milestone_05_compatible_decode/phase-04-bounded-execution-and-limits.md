# Phase 4 — Bounded Pool Execution, Cancellation, and Limits

Back to plan: [README](./README.md)

- [x] 4 Phase - Execute eager decode only as a typed bounded-pool job with
  stable limits, cancellation, redacted telemetry, and exactly-once cleanup.

## 4.1 Section — Native Limits and Cancellation

- [x] 4.1 Section - Apply distinct depth, container, string, and total-output
  statuses and cancellation checkpoints throughout native materialization.
  - [x] 4.1.1 Task - Account nodes, edges, copied keys, and copied strings
    against one checked output budget.
  - [x] 4.1.2 Task - Cancel before traversal, between values and containers,
    and across bounded chunks of large copied byte ranges.

## 4.2 Section — Private Graph-to-BEAM Execution

- [x] 4.2 Section - Convert a complete validated graph into private worker-env
  BEAM terms without publishing partial values.
  - [x] 4.2.1 Task - Build lists and maps iteratively with copied binaries,
    exact scalars, source order, and last duplicate key wins.
  - [x] 4.2.2 Task - Release document, materializer, result, graph frames, and
    the private environment on every success and failure path.

## 4.3 Section — Typed Pool Job and Telemetry

- [x] 4.3 Section - Add decode as an owned typed job in the fixed worker pool
  with FIFO admission, busy rejection, caller monitoring, and cancellation.
  - [x] 4.3.1 Task - Route private decode submission through the existing pool
    with no synchronous or dirty-NIF fallback.
  - [x] 4.3.2 Task - Emit redacted decode queue/execution/outcome telemetry and
    return all lifecycle gauges to baseline.

## 4.4 Section — Phase 4 Integration and Qualification

- [x] 4.4 Section - Reconcile native/runtime sources, package inputs, specs,
  sanitizer evidence, saturation behavior, and qualification state.
  - [x] 4.4.1 Task - Cover success, malformed input, every limit, cancellation,
    saturation, caller death, and shutdown cleanup.
  - [x] 4.4.2 Task - Reconcile manifest, fingerprint, formatting, regressions,
    release symbols, traceability, and SpecLed state.
