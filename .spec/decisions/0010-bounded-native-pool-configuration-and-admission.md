---
id: simd_json.bounded_native_pool_configuration_and_admission
status: accepted
date: 2026-09-03
affects:
  - simd_json.native_pool
  - simd_json.native_execution
  - simd_json.package
---

# Bounded Native Pool Configuration and Admission

## Context

Milestones 1 through 3 use the pinned Zigler threaded facility as a qualified
off-scheduler bridge, but it is not the production admission-control system.
Milestone 4 must establish finite capacity before it replaces that bridge. The
configuration must be deterministic, validated before operation admission,
observable without exposing caller data, and safe on hosts reporting unusually
large scheduler counts.

## Decision

The application accepts exactly two runtime configuration keys:

| Key | Default | Accepted range |
| --- | --- | --- |
| `:native_workers` | `max(1, min(32, div(System.schedulers_online() + 1, 2)))` | `1..64` |
| `:native_queue_size` | `256` | `1..4096` |

Values are integers, not strings, floats, booleans, functions, or deferred
callbacks. Configuration is read and validated once while the application
supervision tree starts, before the operation coordinator accepts work. Invalid
configuration fails startup with a controlled `ArgumentError`; it is never
silently clamped and never falls back to an unbounded or dirty-scheduler path.

The normalized value records the effective worker count and queue capacity plus
whether each value was explicitly configured. Ordinary inspection and the
internal diagnostic snapshot may show only those bounded values and the
executor phase. They do not show environment values, application terms, PIDs,
request references, paths, JSON data, or native addresses.

Phase 1 establishes this contract while explicitly reporting the executor as
`:preproduction_threaded`. Later phases may switch that marker to
`:bounded_native_pool` only when the fixed workers and bounded non-blocking
queue are executing real open, select, and stream jobs. Runtime resizing,
per-operation queues, priorities, caller quotas, and user-defined pool modules
are not part of the initial contract.

Queue saturation will use the stable `SimdJson.Error` reason `:busy`. It means
an otherwise valid operation was not admitted because bounded global capacity
was exhausted. Rejection is immediate, creates no job ownership, and carries no
queue contents or caller identity.

## Consequences

Deployments can plan a hard upper bound before the native pool exists, and
later implementation phases consume one closed normalized representation.
Changing defaults or maxima requires a contract update and renewed saturation,
memory, scheduler, and shutdown qualification.

The first phase does not claim that the configured number of workers exists.
The redacted executor marker prevents configuration plumbing from being
mistaken for production admission control.

