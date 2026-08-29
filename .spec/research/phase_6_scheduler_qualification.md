# Phase 6 Formal Scheduler Qualification

<!-- covers: simd_json.native_execution.threaded_parse simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback simd_json.native_execution.threaded_cleanup simd_json.native_execution.scheduler_qualification simd_json.native_execution.preproduction_boundary simd_json.native_execution.large_parse_responsiveness -->

This note defines the repeatable supported-target scheduler profile that closes
Milestone 1. It replaces the preliminary Phase 4 maximum-only observation with
bounded raw samples, nearest-rank percentiles, separate engineering and noisy-CI
thresholds, scheduler utilization, and a complete environment record.

## Profile

Run:

```console
SIMD_JSON_QUALIFICATION_DIR=_build/qualification/runtime \
  MIX_ENV=test mix test \
  test/qualification/scheduler_qualification_test.exs --seed 0
```

The test warms one valid and one invalid parse before sampling. It then starts
between two and eight valid callers and the same number of invalid callers,
derived from the online normal-scheduler count. Each caller performs 20 rounds
against a 4 MiB logical fixture. A valid round performs public `open/1` plus
`close/1`; an invalid round requires public `open/1` to return
`unexpected_eof`. At eight callers of each kind this is 480 correlated threaded
native entries and 1.25 GiB of aggregate logical parse input.

An independent BEAM process requests a wake-up every 2 ms. The retained raw
intervals are sorted and evaluated with the nearest-rank method. The test also
records aggregate normal, dirty CPU, and dirty I/O scheduler wall-time deltas,
and requires all live operation, retained-input, document, control, dispatcher,
and failed-handoff gauges to return to their pre-profile baseline.

## Budgets

- At least 40 heartbeat samples must be retained.
- The normal-scheduler heartbeat p95 must be at most 50,000 microseconds. This
  is the engineering responsiveness budget.
- The p99 must be at most 250,000 microseconds and the single maximum at most
  500,000 microseconds. These are deliberately wider shared-CI regression
  thresholds, not alternate performance targets.
- Aggregate dirty CPU and dirty I/O active/total ratios must each remain below
  25 percent.

The 50 ms p95 budget is more than six times the Phase 4 development maximum of
7,794 microseconds while remaining small enough to detect normal-scheduler
monopolization. The wider p99 and maximum guards accommodate virtualization,
power management, and neighboring workload on the supported GitHub-hosted
runner. Scheduler wall time alone cannot attribute activity; structural
threaded registration, exact worker-entry accounting, correlated
`worker_context: :threaded` results, and deterministic submission-rejection
tests remain mandatory companion evidence.

## Evidence record

When `SIMD_JSON_QUALIFICATION_DIR` is set, the test writes `scheduler.json`.
The bounded record includes the Git revision, full raw heartbeat sample vector,
percentiles, scheduler utilization, fixture and concurrency profile, OTP/ERTS,
Elixir, OS, architecture, CPU, normal/dirty scheduler counts, virtualization,
power assumptions, and before/after native gauges. CI retains that JSON beside
the command and console log for the immutable PR revision.

## Development observation

The formal profile was exercised on 2026-08-29 from the Phase 6 worktree based
on commit `c2b6508`:

| Input | Observed value |
| --- | --- |
| OS | Linux Mint 22.1, x86-64, no virtualization detected |
| CPU | Intel Core i7-12700F, 20 logical CPUs |
| Runtime | OTP 27.3, ERTS 15.2.3, Elixir 1.18.4 |
| Schedulers | 20 normal / 20 dirty CPU / 10 dirty I/O |
| Workload | 8 valid + 8 invalid callers, 20 rounds, 4 MiB fixture |
| Heartbeat | 92 samples; p50 3,008 us; p95 4,277 us; p99/max 6,282 us |
| Utilization | normal 4.051%; dirty CPU 0.000%; dirty I/O 0.000% |
| Native baseline | every live gauge returned to its pre-profile value |

This observation supports the checked-in budget but is not release evidence.
The immutable Ubuntu 24.04 result archived by the pull-request CI job is the
supported-target record.

The profile does not establish throughput, capacity, backpressure, or overload
behavior. Milestone 1 threading remains qualification-only; the bounded
production worker pool and telemetry are Milestone 4 work.
