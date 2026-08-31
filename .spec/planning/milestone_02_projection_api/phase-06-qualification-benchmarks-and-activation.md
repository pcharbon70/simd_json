# Phase 6 — Qualification, Benchmarks, and Activation

Back to plan: [README](./README.md)

- [x] 6 Phase - Qualify the complete Milestone 2 slice on the supported target,
  demonstrate its sparse-allocation value, and replace planned exceptions with
  executed current truth.

  This phase requalifies ABI version 2 and the packaged native artifact, runs
  the real public path under sanitizers and lifecycle stress, records scheduler
  responsiveness, compares end-to-end projection against Jason full
  materialization, publishes operating and acceptance evidence, and activates
  all three Milestone 2 specs without weakening Milestone 1.

  Contract focus:

  - every requirement and scenario in `simd_json.projection_api`
  - every requirement and scenario in `simd_json.projection_engine`
  - every requirement and scenario in `simd_json.projection_execution`
  - all active Milestone 1 requirements and scenarios as regression gates

## 6.1 Section — Release ABI, Package, and Sanitizer Qualification

- [x] 6.1 Section - Rebuild and inspect the supported release artifact with ABI
  v2, then exercise the complete projection path under native sanitizers.

  This section proves a Hex consumer receives every projection-native input and
  that the same C++/Zig/threaded/public code under qualification remains
  exception-safe, symbol-limited, reproducible, and memory-safe.

  - [x] 6.1.1 Task - Requalify the native artifact and private ABI.

    The task extends the immutable Milestone 1 release matrix rather than
    replacing or bypassing it.

    - [x] 6.1.1.1 Subtask - Add every projection header, source, harness, corpus, script, manifest entry, workflow, benchmark fixture, and acceptance configuration to the qualification fingerprint input set.
    - [x] 6.1.1.2 Subtask - Build the Hex archive, inspect its unpacked inventory, and perform a network-disabled clean consumer compile of ABI v2 from vendored source on Ubuntu 24.04 x86-64.
    - [x] 6.1.1.3 Subtask - Run deterministic and seeded-random C ABI plan/traversal cases, header layout checks, exception/allocation injection, and null/partial/repeated destruction tests.
    - [x] 6.1.1.4 Subtask - Inspect release symbols and strings for the exact ABI v2 allowlist and absence of C++, simdjson internals, projection diagnostics, failure injection, counters, raw paths, and source values.
    - [x] 6.1.1.5 Subtask - Re-run vendor provenance, patch, license, CPU-dispatch, unsupported-target, and pin-change fail-closed checks from Milestone 1.

  - [x] 6.1.2 Task - Run the real projection path under sanitizers.

    The task instruments C++ translation units and Zig/NIF integration while
    executing public binary and document corpora, not a disconnected parser
    kernel.

    - [x] 6.1.2.1 Subtask - Run C ABI plan and traversal harnesses under AddressSanitizer and UndefinedBehaviorSanitizer with malformed descriptors, guard pages, deep paths, borrowed strings, cancellation, and every injected failure edge.
    - [x] 6.1.2.2 Subtask - Run Zig plan/slot ownership and conversion tests under sanitizers with temporary and retained document sources.
    - [x] 6.1.2.3 Subtask - Run isolated threaded and public `select/2` corpora under sanitizers across success, parse/path/type/range failure, cancellation, caller death, close, GC, and shutdown.
    - [x] 6.1.2.4 Subtask - Require no leak, double free, use-after-free, out-of-bounds access, uninitialized read, undefined behavior, C++ exception escape, or stale borrowed-string access.

## 6.2 Section — Scheduler, Lifecycle, and Native Memory Qualification

- [x] 6.2 Section - Record reproducible evidence that large concurrent
  projection remains off scheduler and every lifetime path returns to baseline.

  This section applies the Milestone 1 heartbeat and runtime methodology to
  successful, failing, cancelled, binary, and document projection workloads.

  - [x] 6.2.1 Task - Qualify scheduler responsiveness.

    The task records raw samples and structural worker evidence under the
    supported runtime rather than inferring scheduler safety from throughput.

    - [x] 6.2.1.1 Subtask - Define and record runtime, OS, architecture, scheduler counts, fixture sizes, projection topology, concurrency, warm-up, sample count, and normal/dirty scheduler utilization collection.
    - [x] 6.2.1.2 Subtask - Run independent 2 ms heartbeats while concurrent large valid, malformed, missing-path, wrong-type, cancelled, and binary/document projections execute.
    - [x] 6.2.1.3 Subtask - Preserve the Milestone 1 engineering budget of p95 at or below 50 ms and shared-CI limits of p99 at or below 250 ms and maximum at or below 500 ms unless a superseding accepted decision provides stronger evidence.
    - [x] 6.2.1.4 Subtask - Require dirty CPU and dirty I/O utilization below 25 percent, exact projection worker-entry accounting, one request boundary per selection, and structural proof no ordinary/dirty fallback exists.
    - [x] 6.2.1.5 Subtask - Archive raw latency samples, percentile method, scheduler wall time, command, environment, source revision/tree, fixture digest, and output as immutable CI evidence.

  - [x] 6.2.2 Task - Qualify lifecycle and memory recovery.

    The task runs a seeded bounded stress matrix across every state and
    cancellation boundary and compares all live native gauges with baseline.

    - [x] 6.2.2.1 Subtask - Randomize caller death at every projection boundary, parse/plan/slot/conversion allocation failure, submission rejection, callback-handoff retry, owner/non-owner calls, repeated close, dropped results, and forced GC.
    - [x] 6.2.2.2 Subtask - Mix fresh, selecting, consumed, closing, and closed document sources with temporary binary sources and verify exact consumption, generation isolation, and one cleanup for every created native object.
    - [x] 6.2.2.3 Subtask - Cycle supported application stop/start generations with queued, running, completed, and abandoned projection operations; reject stale delivery and drain before generation advance.
    - [x] 6.2.2.4 Subtask - Await bounded quiescence after every batch and require parser, document, input, plan, node, key-byte, slot, term-environment, operation, retained-resource, dispatcher, and failed-handoff gauges at baseline.
    - [x] 6.2.2.5 Subtask - Record repeated in-process shared-object unload as unsupported unless a real harness exists; do not infer that claim from application restart.

## 6.3 Section — Sparse Benchmark, Documentation, and Spec Activation

- [x] 6.3 Section - Demonstrate the product value end to end, publish operating
  evidence, and make the implemented contracts active.

  This section prevents parser-only microbenchmarks or selective evidence from
  closing the milestone. Fixtures and thresholds are frozen before accepted
  results, and every planned exception is removed only with executable proof.

  - [x] 6.3.1 Task - Freeze and run the Jason comparison.

    The task compares equivalent successful workflows on representative sparse
    documents rather than comparing unrelated parser kernels.

    - [x] 6.3.1.1 Subtask - Pin Jason as a development/benchmark-only dependency and commit deterministic small, medium, and large fixtures with large unselected subtrees, selected paths, expected values, generator seed, and digest.
    - [x] 6.3.1.2 Subtask - Before accepted measurement, commit warm-up, sample, isolation, garbage-collection, memory-sampling, and sparse BEAM-allocation threshold policy without tuning it from observed results.
    - [x] 6.3.1.3 Subtask - Measure `SimdJson.select/2` including validation, scheduling, input copy, plan compilation, full traversal, term construction, and cleanup against `Jason.decode/1` plus equivalent lookups and result retention.
    - [x] 6.3.1.4 Subtask - Record latency, throughput, allocated words/bytes, process and binary memory, native peak/baseline, retained source memory, garbage-collection count/time, reductions, scheduler utilization, and percentile latency.
    - [x] 6.3.1.5 Subtask - Require the predeclared allocation threshold to pass on the sparse fixture and present latency/throughput as measured context rather than claiming unsupported universal superiority.

  - [x] 6.3.2 Task - Publish operations and acceptance records.

    The task makes supported behavior, reproducibility, limitations, and evidence
    discoverable without turning test seams into public runtime features.

    - [x] 6.3.2.1 Subtask - Add a Milestone 2 operations guide containing API grammar, document consumption, duplicate-key behavior, build/test/sanitizer/scheduler/benchmark commands, fixture regeneration, dependency upgrade, and failure triage procedures.
    - [x] 6.3.2.2 Subtask - Add an immutable acceptance record containing source revision/tree, ABI/tool/dependency versions, supported target, qualification fingerprint, seeds/digests, raw artifact locations, thresholds, results, limitations, and exact reproduction commands.
    - [x] 6.3.2.3 Subtask - Update the roadmap, milestone document, README, module docs, ExDoc extras, package metadata, and support statements to mark Milestone 2 active only on the actually qualified target.
    - [x] 6.3.2.4 Subtask - Keep the qualification runtime labeled pre-production and explicitly defer compiled plans, streaming, eager decode, worker-pool admission, backpressure, and telemetry.

  - [x] 6.3.3 Task - Activate Milestone 2 current truth.

    The task replaces bootstrap allowances with executed verification and audits
    every new and inherited contract against the final artifact.

    - [x] 6.3.3.1 Subtask - Add evidence inventories and one or more executable qualification commands covering every Projection API, Projection Engine, and Projection Execution requirement and scenario.
    - [x] 6.3.3.2 Subtask - Set all three subjects to `active`, require executed verification strength, and remove their Milestone 2 bootstrap exceptions in the same change.
    - [x] 6.3.3.3 Subtask - Audit every `covers:` marker, spec decision link, status, source surface, test target, command, roadmap link, and plan checkbox against generated SpecLed state.
    - [x] 6.3.3.4 Subtask - Confirm all active Milestone 1 subjects and gates remain green after ABI v2, document state, error vocabulary, and public surface reconciliation.

## 6.4 Section — Phase 6 Integration Tests

- [x] 6.4 Section - Execute one master acceptance gate over release packaging,
  native safety, public behavior, lifecycle, scheduler responsiveness,
  benchmarks, documentation, and SpecLed activation.

  This section produces the final immutable evidence bundle and is the only gate
  that can declare Milestone 2 complete.

  - [x] 6.4.1 Task - Run the complete supported-target qualification matrix.

    The task starts from a clean checkout and executes every focused command
    used by the active specs against the same source revision.

    - [x] 6.4.1.1 Subtask - Verify vendored source and qualification fingerprint, build and inspect the Hex package offline, compile ABI v2, and run C/Zig ordinary and sanitizer suites.
    - [x] 6.4.1.2 Subtask - Run projection grammar, engine, threaded, API, error, ownership, consumption, cleanup, malformed corpus, atom-safety, retained-memory, and public-surface tests plus every Milestone 1 regression suite.
    - [x] 6.4.1.3 Subtask - Run scheduler/lifecycle qualification and the frozen Jason sparse benchmark, enforce every committed threshold, and archive raw evidence with revision and environment identity.
    - [x] 6.4.1.4 Subtask - Run `mix format --check-formatted`, documentation generation with warnings as errors, static analysis configured by the repository, and the complete `mix test` suite.

  - [x] 6.4.2 Task - Close traceability and publish the acceptance result.

    The task proves implementation, documentation, plans, and generated state
    agree with no remaining exception or unverified claim.

    - [x] 6.4.2.1 Subtask - Run `mix spec.index`, structural `mix spec.validate --debug --min-strength claimed`, structural `mix spec.status --no-run-commands --min-strength claimed`, `mix spec.next`, and the exact reported `mix spec.check --base ...` command with zero errors or warnings; keep `spec.check` last so its executed verification is the canonical state.
    - [x] 6.4.2.2 Subtask - Run the repository traceability verifier and require every Milestone 2 subject active, executed, linked to accepted decisions, and free of exceptions or uncovered requirements.
    - [x] 6.4.2.3 Subtask - Verify every Phase 1–6 checkbox has corresponding committed implementation and executed evidence before marking it complete.
    - [x] 6.4.2.4 Subtask - Publish the final CI evidence bundle and record its workflow run, artifact digests, supported target, benchmark threshold result, known limitations, and source revision in the acceptance document.
