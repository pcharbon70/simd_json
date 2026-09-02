# Phase 6 — Qualification, ETL Benchmarks, and Activation

Back to plan: [README](./README.md)

- [ ] 6 Phase - Qualify the complete Milestone 3 slice on the supported target,
  demonstrate bounded-memory array ETL, and replace planned exceptions with
  executed current truth.

  This phase requalifies ABI v3 and the packaged artifact, runs public streaming
  under sanitizers and seeded lifecycle stress, records scheduler and
  slow-consumer behavior, compares complete reduction against Jason full
  materialization, publishes operations/acceptance evidence, and activates all
  three Milestone 3 specs without weakening prior milestones.

  Contract focus:

  - every requirement and scenario in `simd_json.streaming_api`
  - every requirement and scenario in `simd_json.stream_cursor`
  - every requirement and scenario in `simd_json.stream_execution`
  - all active Milestone 1 and 2 requirements and scenarios as regression gates

## 6.1 Section — Release ABI, Package, and Sanitizer Qualification

- [x] 6.1 Section - Rebuild and inspect the supported release artifact with ABI
  v3 and exercise the complete cursor/batch/Enumerable path under native
  sanitizers.

  This section proves a package consumer receives every streaming-native input
  and that the qualified C++/Zig/threaded/public code is exception-safe,
  symbol-limited, reproducible, and memory-safe.

  - [x] 6.1.1 Task - Requalify the native artifact and private ABI.

    The task extends the cumulative release matrix rather than replacing ABI
    v1/v2 or bypassing earlier package proof.

    - [x] 6.1.1.1 Subtask - Add every streaming ADR, spec, plan, header, source, harness, script, workflow, fixture, policy, public test, operations guide, and acceptance input to the qualification fingerprint.
    - [x] 6.1.1.2 Subtask - Build and inspect the Hex archive and perform a network-disabled clean consumer compile of ABI v3 from vendored source on Ubuntu 24.04 x86-64.
    - [x] 6.1.1.3 Subtask - Run deterministic and seeded-random target/cursor/batch cases, layout checks, limit arithmetic, state transitions, exception/allocation injection, and null/partial/repeated destruction tests.
    - [x] 6.1.1.4 Subtask - Inspect release symbols and strings for exact cumulative allowlists and absence of C++/simdjson internals, source/options, cursor diagnostics, failure controls, counters, raw paths, keys, values, and owner identity.
    - [x] 6.1.1.5 Subtask - Re-run vendor provenance, patch, license, CPU-dispatch, unsupported-target, offline reproducibility, and pin-change fail-closed gates from Milestones 1 and 2.

  - [x] 6.1.2 Task - Run the real stream path under sanitizers.

    The task instruments native translation units and NIF integration while
    executing public Enumerable behavior rather than a disconnected cursor
    micro-kernel.

    - [x] 6.1.2.1 Subtask - Run C ABI cursor/batch harnesses under AddressSanitizer and UndefinedBehaviorSanitizer with invalid descriptors, guard pages, deep targets, huge strings, exact limits, cancellation, and every injected failure edge.
    - [x] 6.1.2.2 Subtask - Run Zig cursor-parent ownership, plan reuse, batch conversion, copied-string, state, and teardown suites under sanitizers for binary and retained document sources.
    - [x] 6.1.2.3 Subtask - Run isolated threaded and public `stream/2` corpora under sanitizers across done, parse/path/type/range/size failure, slow consumer, cancellation, halt, exception/death, close, GC, and shutdown.
    - [x] 6.1.2.4 Subtask - Require no leak, double free, use-after-free, out-of-bounds access, integer overflow, uninitialized read, undefined behavior, C++ exception escape, stale iterator, parent pointer, borrowed string, or batch view.

## 6.2 Section — Scheduler, Demand, Lifecycle, and Memory Qualification

- [x] 6.2 Section - Record reproducible evidence that concurrent streaming
  remains off scheduler, obeys local demand, and returns every long-lived native
  graph to baseline.

  This section extends the accepted heartbeat and lifecycle methodology to
  setup plus thousands of bounded batches, idle consumers, early exits, and
  mid-stream failures.

  - [x] 6.2.1 Task - Qualify scheduler responsiveness and boundary accounting.

    The task records raw samples and structural threaded proof under the
    supported runtime instead of inferring safety from throughput.

    - [x] 6.2.1.1 Subtask - Predeclare and record runtime, OS, architecture, scheduler counts, fixtures, target/field topology, batch limits, concurrency, warm-up, samples, percentile method, and normal/dirty utilization collection.
    - [x] 6.2.1.2 Subtask - Run independent 2 ms heartbeats with concurrent large full, malformed, wrong-type, oversized-row, slow, early-halted, consumer-dead, and cancelled binary/document streams.
    - [x] 6.2.1.3 Subtask - Preserve p95 at or below 50 ms, p99 at or below 250 ms, maximum at or below 500 ms, and dirty CPU/I/O utilization below 25 percent unless a superseding accepted decision sets stronger evidence-based budgets.
    - [x] 6.2.1.4 Subtask - Require exact setup, plan, row, and batch worker accounting, one boundary per setup/batch, no per-row/field entry, and structural proof of no ordinary/dirty fallback.
    - [x] 6.2.1.5 Subtask - Archive raw latency, scheduler wall time, batch sequences/sizes/bytes, command, environment, source revision/tree, fixture digest, and result as immutable CI evidence.

  - [x] 6.2.2 Task - Qualify local demand and slow-consumer behavior.

    The task proves that an Enumerable pause is a real native progress boundary
    and not merely delayed delivery after hidden prefetch.

    - [x] 6.2.2.1 Subtask - Pause consumers before reduction, within returned lists, and between batches while sampling cursor index, setup/batch entries, native allocations, coordinator requests, and process mailbox length.
    - [x] 6.2.2.2 Subtask - Require zero native setup for unreduced streams, one active and one returned batch maximum, no next sequence during pause, and no stream-specific message or allocation growth over the current batch.
    - [x] 6.2.2.3 Subtask - Resume each paused consumer and require exact row order, no duplicate or missing index, correct sequence, and final cleanup without a catch-up prefetch burst.
    - [x] 6.2.2.4 Subtask - Record that these results prove only per-stream demand and do not claim Milestone 4 global admission, queue capacity, fairness, or telemetry.

  - [x] 6.2.3 Task - Qualify lifecycle, cancellation, and memory recovery.

    The task runs a seeded bounded matrix across every state, source, batch, and
    reducer terminal path and compares the complete native graph with baseline.

    - [x] 6.2.3.1 Subtask - Randomize halt, exception, and caller death at every setup/target/row/projection/conversion/delivery/finalization boundary plus every reachable allocation and submission failure.
    - [x] 6.2.3.2 Subtask - Mix unreduced, ready, running, done, cancelled, and closed streams with fresh/selecting/streaming/consumed/closing/closed documents, binary graphs, select races, repeated cleanup, dropped terms, and forced GC.
    - [x] 6.2.3.3 Subtask - Cycle supported application stop/start generations with idle, queued, running, returned, suspended, abandoned, and completed cursors; reject stale delivery and drain before generation advance.
    - [x] 6.2.3.4 Subtask - Await bounded quiescence after every batch and require input, parser, document, cursor, frame, plan, node, key-byte, row, slot, string, batch, environment, operation, retained-resource, dispatcher, and failed-handoff gauges at baseline.
    - [x] 6.2.3.5 Subtask - Record repeated in-process shared-object unload as unsupported unless a real OS-loader harness exists; do not infer it from application restart.

## 6.3 Section — ETL Benchmark, Documentation, and Spec Activation

- [x] 6.3 Section - Demonstrate bounded-memory product value end to end,
  publish reproducible operating evidence, and make implemented contracts
  active.

  This section prevents parser-only or throughput-only results from closing the
  milestone. Fixtures, reduction, batch matrix, samples, and thresholds are
  frozen before accepted measurements.

  - [x] 6.3.1 Task - Freeze and run the Jason array ETL comparison.

    The task compares equivalent successful and early-halt workflows rather
    than a native batch kernel against an unrelated decode call.

    - [x] 6.3.1.1 Subtask - Commit deterministic small, medium, and million-row sparse array fixtures with root/nested variants, large unselected fields, selected paths, expected reduction digest, huge-row cases, generator seed, and source digest.
    - [x] 6.3.1.2 Subtask - Before measurement, commit pinned Jason version, equivalent lookup/projection/reduction work, batch-size matrix, row/byte limits, warm-up, samples, GC/isolation/memory policy, early-halt points, and bounded-memory acceptance thresholds.
    - [x] 6.3.1.3 Subtask - Measure `SimdJson.stream/2` including validation, lazy setup, input copy, target lookup, plan compilation, every batch, row conversion, consumer reduction, final validation, and cleanup against Jason full decode plus equivalent operations.
    - [x] 6.3.1.4 Subtask - Record time to first row/batch, total latency, rows/input bytes per second, batch crossings, p50/p95/p99, process/binary/RSS/native peaks and baselines, retained input, allocated words/bytes, GC count/time, reductions, and scheduler utilization.
    - [x] 6.3.1.5 Subtask - Require memory to remain within the predeclared flat-per-batch envelope across thousands of batches and pass the declared large-fixture advantage over Jason; present latency/throughput as measured context rather than universal superiority.

  - [x] 6.3.2 Task - Publish stream operations and acceptance records.

    The task makes API behavior, tuning, reproduction, limitations, and evidence
    discoverable without turning test seams into product features.

    - [x] 6.3.2.1 Subtask - Add a Milestone 3 operations guide covering options, defaults, root/nested targets, ownership, document consumption, errors, early halt, bounds, tuning, build/test/sanitizer/scheduler/demand/benchmark commands, fixture regeneration, upgrades, and failure triage.
    - [x] 6.3.2.2 Subtask - Add an immutable acceptance record with source revision/tree, ABI/tool/dependency versions, target, qualification fingerprint, seeds/digests, artifact locations, thresholds, batch/memory/scheduler results, limitations, and exact reproduction commands.
    - [x] 6.3.2.3 Subtask - Update roadmap, milestone, README, module docs, ExDoc extras, package metadata, and support statements to mark Milestone 3 active only on the actually qualified target.
    - [x] 6.3.2.4 Subtask - Keep the runtime labeled pre-production and explicitly defer batch API, raw cursor, prefetch, transfer, checkpoint/resume, parallel array work, eager decode, global worker admission, and telemetry.

  - [x] 6.3.3 Task - Activate Milestone 3 current truth.

    The task replaces bootstrap allowances with executed verification and
    audits every new and inherited contract against the final artifact.

    - [x] 6.3.3.1 Subtask - Add evidence inventories and executable qualification commands covering every Streaming API, Stream Cursor, and Stream Execution requirement and scenario.
    - [x] 6.3.3.2 Subtask - Set all three subjects to `active`, require executed verification strength, and remove their Milestone 3 bootstrap exceptions in the same change.
    - [x] 6.3.3.3 Subtask - Audit every `covers:` marker, decision link, status, surface, test target, command, roadmap link, plan checkbox, and generated SpecLed edge.
    - [x] 6.3.3.4 Subtask - Confirm every active Milestone 1 and 2 subject and qualification gate remains green after ABI v3, document use state, error metadata, Enumerable protocol, and public surface reconciliation.

## 6.4 Section — Phase 6 Integration Tests

- [ ] 6.4 Section - Execute one master acceptance gate over release packaging,
  native safety, public behavior, demand, lifecycle, scheduler responsiveness,
  bounded memory, ETL benchmarks, documentation, and SpecLed activation.

  This section produces the immutable evidence bundle and is the only gate that
  can declare Milestone 3 complete.

  - [ ] 6.4.1 Task - Run the complete supported-target qualification matrix.

    The task starts from a clean checkout and executes every focused command
    used by active specs against one source revision.

    - [ ] 6.4.1.1 Subtask - Verify vendor and qualification fingerprint, build/inspect the Hex package offline, compile ABI v3, and run cumulative C/Zig ordinary and sanitizer suites.
    - [ ] 6.4.1.2 Subtask - Run option, cursor, batch, Enumerable, error, ownership, select/stream exclusion, demand, halt, cleanup, malformed corpus, atom-safety, retained-memory, and public-surface tests plus every Milestone 1/2 regression.
    - [ ] 6.4.1.3 Subtask - Run scheduler, slow-consumer, lifecycle, and frozen Jason ETL qualification, enforce every committed threshold, and archive raw revision/environment-bound evidence.
    - [ ] 6.4.1.4 Subtask - Run `mix format --check-formatted`, documentation generation with warnings as errors, repository static analysis, and the complete `mix test` suite.

  - [ ] 6.4.2 Task - Close traceability and publish acceptance.

    The task proves implementation, documentation, decisions, plans, specs, and
    generated state agree with no remaining exception or unverified claim.

    - [ ] 6.4.2.1 Subtask - Run `mix spec.index`, structural `mix spec.validate --debug --min-strength claimed`, structural `mix spec.status --no-run-commands --min-strength claimed`, `mix spec.next`, and the exact reported `mix spec.check --base ...` with zero errors/warnings; keep `spec.check` last for canonical executed state.
    - [ ] 6.4.2.2 Subtask - Run the repository traceability verifier and require all Milestone 3 subjects active, executed, linked to accepted decisions, and free of exceptions or uncovered requirements.
    - [ ] 6.4.2.3 Subtask - Verify every Phase 1–6 checkbox has corresponding committed implementation and executed evidence before marking it complete.
    - [ ] 6.4.2.4 Subtask - Publish the final CI evidence bundle and record workflow run, artifact digests, supported target, ETL/memory threshold results, known limitations, and source revision in the acceptance document.
