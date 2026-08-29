# Phase 6 — Qualification and Milestone Activation

Back to plan: [README](./README.md)

- [ ] 6 Phase - Qualify the complete vertical slice, publish reproducible evidence, and activate Milestone 1 current truth.

  This phase repeats the earlier safety gates against the final public artifact,
  establishes the supported-target and scheduler budgets, stress-tests shutdown
  and cleanup, and reconciles every requirement and scenario with executed
  proof. Only after all gates pass are the four planned subjects changed to
  active and their bootstrap exceptions removed.

  Contract focus:

  - `simd_json.native_build_and_abi.milestone_01_bootstrap`
  - `simd_json.document_resource.milestone_01_bootstrap`
  - `simd_json.native_execution.milestone_01_bootstrap`
  - `simd_json.document_api.milestone_01_bootstrap`
  - all requirements and scenarios owned by the preceding five phases

## 6.1 Section — Release Native and Platform Qualification

- [x] 6.1 Section - Prove the packaged native artifact is reproducible, portable within its declared matrix, and sanitizer-clean.

  This section qualifies actual release outputs rather than developer build
  intermediates. Every supported target receives the same provenance, ABI,
  symbol, parser-conformance, and safety treatment; targets without equivalent
  evidence remain explicitly unsupported or experimental.

  - [x] 6.1.1 Task - Run the supported-target clean-build matrix.

    The task re-executes `clean_supported_build` and
    `unsupported_target_rejection` for the complete package in isolated CI
    environments.

    - [x] 6.1.1.1 Subtask - Build from clean source on every supported operating-system and architecture target with no system simdjson and no build-time network access after normal dependency fetch.
    - [x] 6.1.1.2 Subtask - Verify the compiler, Zig, Zigler, simdjson source digest, flags, runtime ABI, and CPU-dispatch implementation against the checked-in qualification matrix.
    - [x] 6.1.1.3 Subtask - Build the distributable package, inspect its contents, and prove all required native sources, headers, provenance, licenses, notices, and build inputs are present.
    - [x] 6.1.1.4 Subtask - Exercise unsupported-target guards and prove no system library, generic unqualified artifact, or alternate scheduler mode is selected.

  - [x] 6.1.2 Task - Run final C ABI and native safety qualification.

    The task re-executes `c_abi_conformance`, `cpp_exception_translation`, and
    `release_symbol_surface` against the same sources and profiles used by the
    package.

    - [x] 6.1.2.1 Subtask - Run the independent C harness for all valid roots, malformed inputs, invalid pointer-length combinations, injected exceptions, allocation failures, and destruction paths.
    - [x] 6.1.2.2 Subtask - Run native, Zig resource, threaded operation, and public API corpora under AddressSanitizer and UndefinedBehaviorSanitizer on every target that supports those tools.
    - [x] 6.1.2.3 Subtask - Add bounded randomized malformed-input and lifecycle-sequence stress without treating a fuzzer crash-free run as a substitute for required deterministic cases.
    - [x] 6.1.2.4 Subtask - Inspect release symbols and strings to prove C++ implementation details, test hooks, allocation counters, failure injection, native addresses, and exception text are absent.
    - [x] 6.1.2.5 Subtask - Archive target, command, seed, tool version, source digest, and sanitizer output as reviewable qualification evidence.

  - [x] 6.1.3 Task - Verify the dependency-upgrade gate.

    The task proves `dependency_upgrade_gate` is an executable maintenance rule,
    not prose that can be skipped during a later simdjson or toolchain update.

    - [x] 6.1.3.1 Subtask - Add CI change detection for vendored simdjson, patch manifests, Zig, Zigler, compiler profiles, C header layouts, and target matrix inputs.
    - [x] 6.1.3.2 Subtask - Require changed inputs to invalidate clean-build, C ABI, sanitizer, CPU-dispatch, scheduler, and package evidence.
    - [x] 6.1.3.3 Subtask - Test the gate with an isolated pin change and assert stale qualification artifacts cannot satisfy it.

## 6.2 Section — Scheduler, Lifecycle, and Memory Qualification

- [x] 6.2 Section - Prove the final public API remains responsive and leak-free under realistic concurrency and teardown races.

  This section turns scheduler safety into repeatable measured evidence. It
  records enough environment data to interpret latency results and treats dirty
  scheduler consumption, orphaned native work, and memory retained after
  quiescence as failures.

  - [x] 6.2.1 Task - Establish and run the scheduler-responsiveness qualification profile.

    The task executes the final `large_parse_responsiveness` scenario with a
    documented budget chosen from stable qualification-host measurements rather
    than an unexplained timing constant.

    - [x] 6.2.1.1 Subtask - Record OTP/ERTS, operating system, architecture, CPU, normal and dirty scheduler counts, power/virtualization assumptions, fixture sizes, concurrency, warm-up, sample count, and percentile calculation.
    - [x] 6.2.1.2 Subtask - Select and document a normal-scheduler heartbeat latency budget and a separate non-flaky CI regression threshold derived from the qualification profile.
    - [x] 6.2.1.3 Subtask - Open and close large valid and invalid documents concurrently while independent BEAM processes measure wake-up latency and scheduler utilization.
    - [x] 6.2.1.4 Subtask - Assert heartbeat percentiles stay within budget, ordinary NIF entry remains bounded, and dirty schedulers do not carry JSON parse or large-cleanup load.
    - [x] 6.2.1.5 Subtask - Retain raw bounded measurements and summarized results so a future toolchain or execution change can be compared against the same protocol.

  - [x] 6.2.2 Task - Stress cancellation, teardown, and native baseline recovery.

    The task combines `caller_dies_while_running`, `threaded_submission_failure`,
    `large_gc_teardown`, `reload_cleanup`, `repeated_close`, and
    `native_memory_baseline` in long-running but bounded qualification loops.

    - [x] 6.2.2.1 Subtask - Randomize caller death and explicit close around each cancellation boundary while valid and invalid parses are queued or running.
    - [x] 6.2.2.2 Subtask - Inject parse and cleanup submission failures and assert no scheduler fallback, partial publication, stale delivery, or retained operation survives quiescence.
    - [x] 6.2.2.3 Subtask - Mix owner close, repeated close, non-owner close, dropped resource terms, and forced GC across independent documents and assert exactly-once reverse destruction.
    - [x] 6.2.2.4 Subtask - Repeat application stop/start and supported NIF load/unload with queued, running, delivered, and abandoned work; assert generations isolate every completion.
    - [x] 6.2.2.5 Subtask - After each stress batch, await bounded cleanup quiescence and prove buffers, parser/document handles, resources, retained parents, operations, and result environments return to baseline.

## 6.3 Section — Documentation, Traceability, and Spec Activation

- [x] 6.3 Section - Reconcile implemented behavior and evidence back into the milestone, ADRs, specs, and package documentation.

  This section makes current truth honest. It updates descriptions where
  implementation selected an allowed detail, records supported limitations, and
  removes planned exceptions only when machine-linked executed evidence covers
  every obligation.

  - [x] 6.3.1 Task - Publish implementation and operational documentation.

    The task gives maintainers enough detail to upgrade or extend the resource
    safely and gives callers an accurate pre-production Milestone 1 contract.

    - [x] 6.3.1.1 Subtask - Document the final source layout, build inputs, target matrix, CPU-dispatch diagnostics, native dependency update procedure, and sanitizer commands.
    - [x] 6.3.1.2 Subtask - Document the C ABI handle graph, status map, exception boundary, padded allocation contract, resource fields, lifecycle transitions, generation rules, and reverse-destruction order.
    - [x] 6.3.1.3 Subtask - Document threaded request correlation, cancellation boundaries, GC handoff, shutdown/unload behavior, scheduler qualification environment, and latency budget.
    - [x] 6.3.1.4 Subtask - Document `open/1`, `close/1`, structured error reasons, offset semantics, redaction, owner rules, deterministic close, and the absence of later-milestone APIs.
    - [x] 6.3.1.5 Subtask - State explicitly that Milestone 1 threading is qualification-only and that production capacity bounds, backpressure, and telemetry depend on Milestone 4.

  - [x] 6.3.2 Task - Reconcile every requirement and scenario with executed proof.

    The task prevents a bootstrap exception or checked planning box from being
    mistaken for verification.

    - [x] 6.3.2.1 Subtask - Generate a requirement-to-test and scenario-to-test inventory for all four Milestone 1 subjects and reject missing, stale, or test-only-assertion-free links.
    - [x] 6.3.2.2 Subtask - Confirm native commands, sanitizer jobs, scheduler evidence, symbol inspection, clean builds, doctests, public tests, and documentation checks are represented in SpecLed verification.
    - [x] 6.3.2.3 Subtask - Remove `simd_json.native_build_and_abi.milestone_01_bootstrap` only after every Native Build and ABI requirement and scenario has executed proof.
    - [x] 6.3.2.4 Subtask - Remove `simd_json.document_resource.milestone_01_bootstrap` only after every Document Resource requirement and scenario has executed proof.
    - [x] 6.3.2.5 Subtask - Remove `simd_json.native_execution.milestone_01_bootstrap` only after every Native Execution requirement and scenario has executed proof.
    - [x] 6.3.2.6 Subtask - Remove `simd_json.document_api.milestone_01_bootstrap` only after every Document API and Errors requirement and scenario has executed proof.
    - [x] 6.3.2.7 Subtask - Change each subject from `planned` to `active` in the same reconciled change, regenerate `.spec/state.json`, and require zero errors, warnings, uncovered policy files, and weak spots.

  - [x] 6.3.3 Task - Audit Milestone 1 scope and Milestone 2 readiness.

    The task closes the foundation only if later traversal can retain the parent
    resource without revising build, ownership, lifecycle, or scheduler
    fundamentals.

    - [x] 6.3.3.1 Subtask - Enumerate release modules, functions, types, NIF entries, dynamic symbols, and documentation against the Milestone 1 surface allowlists.
    - [x] 6.3.3.2 Subtask - Confirm no eager decode, projection, stream, cursor, ownership transfer, raw handle, final worker pool, backpressure, or telemetry behavior landed early.
    - [x] 6.3.3.3 Subtask - Review the parent-retention and generation helpers against Milestone 2's cursor needs without adding or exposing a cursor in this phase.
    - [x] 6.3.3.4 Subtask - Update the Milestone 1 completion criteria with links to final evidence and record any still-unsupported target without overstating package support.

## 6.4 Section — Phase 6 Integration Tests

- [ ] 6.4 Section - Execute the complete release-candidate gate and produce the Milestone 1 acceptance record.

  This section runs every layer together from clean package build through
  public API, scheduler stress, cleanup quiescence, and SpecLed validation. Any
  failure reopens its owning phase and prevents spec activation.

  - [ ] 6.4.1 Task - Run the full release-candidate verification matrix.

    The task proves all accepted decisions and all four subject specs against one
    immutable source revision.

    - [ ] 6.4.1.1 Subtask - Run provenance, vendor checksum, patch, license, offline clean-build, target guard, runtime-dispatch, package-content, and release-symbol checks.
    - [ ] 6.4.1.2 Subtask - Run the independent C ABI harness plus Zig resource and failure-injection suites in ordinary, AddressSanitizer, and UndefinedBehaviorSanitizer profiles.
    - [ ] 6.4.1.3 Subtask - Run the complete public valid/invalid corpus, argument, redaction, owner, lifecycle, concurrent-open, caller-death, submission-failure, GC, baseline, shutdown, and reload suites.
    - [ ] 6.4.1.4 Subtask - Run the formal scheduler qualification and assert the recorded normal-scheduler latency and dirty-scheduler utilization budgets.
    - [ ] 6.4.1.5 Subtask - Run formatting, documentation/link checks, `mix test`, package build, and every supported-target CI job from the same release candidate.

  - [ ] 6.4.2 Task - Run final SpecLed reconciliation and close the milestone.

    The task makes the acceptance result visible in current truth and leaves no
    bootstrap exception masking unimplemented behavior.

    - [ ] 6.4.2.1 Subtask - Run `mix spec.next` and resolve every requested subject or decision reconciliation without weakening an accepted safety boundary.
    - [ ] 6.4.2.2 Subtask - Run the reported `mix spec.check --base ...` command and require zero errors, warnings, findings, uncovered policy files, and weak spots.
    - [ ] 6.4.2.3 Subtask - Confirm all four subjects are active, all four Milestone 1 bootstrap exceptions are absent, and generated state links every requirement and scenario to executed proof.
    - [ ] 6.4.2.4 Subtask - Record the immutable release revision, supported-target matrix, complete command list, CI artifacts, sanitizer summaries, scheduler measurements, memory-baseline result, and remaining non-goals in the Milestone 1 acceptance record.
