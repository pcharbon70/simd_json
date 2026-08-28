# Phase 4 Preliminary Scheduler Qualification

<!-- covers: simd_json.native_execution.threaded_parse simd_json.native_execution.bounded_nif_entry simd_json.native_execution.no_fallback simd_json.native_execution.threaded_cleanup simd_json.native_execution.scheduler_qualification simd_json.native_execution.preproduction_boundary simd_json.native_execution.large_parse_responsiveness -->

This note fixes the repeatable Phase 4 scheduler-responsiveness profile for the
internal document operation. It is preliminary evidence for the execution
substrate, not the formal supported-target qualification assigned to Phase 6.

## Automated profile

Run:

```text
MIX_ENV=test mix test test/native/native_execution_integration_test.exs
```

The test constructs its fixtures before sampling begins. A valid JSON document
is at least 4 MiB, and the invalid fixture is the same binary without its final
array delimiter. It starts between two and eight valid callers and the same
number of invalid callers, derived from the online normal-scheduler count. Each
caller performs three rounds. A valid round opens and closes a document; an
invalid round runs an open that must return `unexpected_eof`. With eight callers
of each kind, this produces 48 parse entries plus 24 cleanup entries, for 72
threaded native entries and 192 MiB of aggregate logical parse input.

An independent BEAM process samples its wake-up interval every 5 ms. The test
also enables `scheduler_wall_time_all` immediately around the workload and
records aggregate active/total deltas for normal, dirty CPU, and dirty I/O
schedulers. Scheduler identifiers are partitioned using the runtime's normal,
dirty CPU, and dirty I/O scheduler counts.

The Phase 4 regression thresholds are:

- maximum observed heartbeat interval below 500,000 microseconds;
- aggregate dirty CPU active/total ratio below 25 percent;
- aggregate dirty I/O active/total ratio below 25 percent;
- every expected operation enters the native worker counter, returns through
  the coordinator's `:threaded` context check, and restores all live document,
  control, operation, input, and dispatcher counters to baseline.

The deliberately wide thresholds distinguish a scheduler-blocking regression
from ordinary shared-runner noise. They are not a throughput target or the
formal percentile budget required in Phase 6. Structural tests additionally
reject ordinary, dirty CPU, or dirty I/O registration for the parse and cleanup
entrypoints. Controlled submission rejection proves the implementation returns
`%{reason: :native_failure, stage: :threaded_submission}` before native worker
entry and never selects another execution mode.

## Development observation

The profile was executed on 2026-08-28 with this environment:

| Input | Observed value |
| --- | --- |
| OS | Linux Mint 22.1, Ubuntu Noble base, Linux 6.8.0-51, x86_64 |
| CPU | Intel Core i7-12700F, 12 cores / 20 logical CPUs |
| BEAM | OTP 27.3, ERTS 15.2.3, 20 normal / 20 dirty CPU / 10 dirty I/O schedulers |
| Elixir | 1.18.4 |
| Native pins | Zigler 0.16.0, Zig 0.16.0, simdjson 4.6.9 |
| Workload | 8 valid + 8 invalid callers, 3 rounds, 4 MiB fixture |
| Result | 8 heartbeat samples; maximum interval 7,794 us; normal 5.052%; dirty CPU 0.000%; dirty I/O 0.005% |

CI repeats the same dynamic profile on the pinned Ubuntu 24.04 x86_64 target
and emits one `phase4_scheduler` line with the runtime, workload, heartbeat,
and scheduler measurements. A code, dependency, or runner change must satisfy
the automated thresholds again; this local observation is never substituted
for the current CI run.

## Interpretation and remaining boundary

Scheduler wall time cannot attribute unrelated dirty-scheduler activity to one
library, so the utilization threshold is paired with registration inspection,
thread-context correlation, exact worker-entry accounting, and controlled
submission failure. The rejection setter and injected raise are compiled only
in `MIX_ENV=test`; a production compilation does not export the setter. Phase 6
must replace the preliminary maximum-interval gate with a sufficiently sampled
percentile profile, record power and virtualization assumptions, and establish
the final supported-target budget.

This workload intentionally provides no production queue limit or backpressure.
The fixed native parse pool, bounded admission, telemetry, and overload policy
remain Milestone 4 responsibilities.
