# Native Execution

Current-truth contract for scheduler isolation, threaded request correlation, cancellation-safe retention, and scheduler responsiveness during Milestone 1.

## Intent

This subject ensures that proving the native parser never makes unrelated BEAM processes pay an input-dependent scheduling cost and that asynchronous completion cannot outlive the resources it uses.

Phases 1 through 3 contribute bounded build/resource diagnostics and native
ownership tests outside the BEAM. Phase 4 now qualifies the pinned Zigler
contexts and connects bounded admission to real threaded document construction.
A private environment retains the binary term without copying its bytes; the
worker alone creates the owned padded copy and invokes the C ABI. A stable
coordinator owns the generated Zigler thread through join, correlates private
kind/reference/generation, monitors the original caller, and discards or
off-scheduler-cleans orphan results. Deterministic boundary tests cover caller
death before copy, before and after parse, before publication, and before
delivery. Resource callbacks now detach into a cleanup-only dispatcher, failed
handoff retains ownership for retry, repeated explicit close joins one cleanup,
and application stop drains work before advancing the native generation. The
unload callback drains and joins the dispatcher, although repeated in-process
shared-object unload is not supported by the qualified OTP harness. Controlled
parse and cleanup submission rejection, repeated application generations,
correlation races, large-resource GC, and a preliminary heartbeat plus
normal/dirty scheduler-utilization profile now close the Phase 4 integration
section. Phase 5 Section 5.1 routes the binary public open and accepted owner
close directly through that coordinator. Non-binary, forged-document, and
non-owner calls stop before threaded admission; the bounded owner NIF reads no
input-dependent state and checks owner before lifecycle. Section 5.2 verifies
that rejected submissions and every native failure class return through the
same redacted public translator without synchronous fallback. Section 5.3
labels this threaded layer as a qualification runtime and assigns production
admission control and its bounded worker pool to Milestone 4. The formal Phase
6 scheduler profile and the recorded repeated-unload qualification gap keep the
bootstrap exception in force.

```spec-meta
id: simd_json.native_execution
kind: subsystem
status: planned
summary: Input-dependent parse and cleanup work execute through a correlated Zigler-threaded boundary outside normal and dirty schedulers.
surface:
  - native/**
  - lib/simd_json/**/*.ex
  - test/**/*scheduler*
  - test/**/*native_execution*
  - docs/milestones/01-native-foundation.md
decisions:
  - simd_json.off_scheduler_native_execution
```

## Requirements

```spec-requirements
- id: simd_json.native_execution.threaded_parse
  statement: Milestone 1 shall run input-dependent parsing through the pinned Zigler threaded execution facility rather than an ordinary or dirty CPU NIF.
  priority: must
  stability: evolving

- id: simd_json.native_execution.bounded_nif_entry
  statement: Ordinary NIF entrypoints shall perform only bounded validation, resource retention, request correlation, submission, state transition, and bounded result marshalling.
  priority: must
  stability: stable

- id: simd_json.native_execution.no_fallback
  statement: Failure to submit threaded work shall return a structured error and shall never fall back to input-dependent work on a normal or dirty scheduler.
  priority: must
  stability: stable

- id: simd_json.native_execution.request_correlation
  statement: Each threaded operation shall use an unforgeable unique reference so only its matching result can complete the waiting Elixir call.
  priority: must
  stability: stable

- id: simd_json.native_execution.retained_resources
  statement: Every queued or running threaded operation shall retain all document and input resources it can dereference until its terminal cleanup completes.
  priority: must
  stability: stable

- id: simd_json.native_execution.late_result_cleanup
  statement: Late, duplicate, mismatched, timed-out, cancelled, or caller-orphaned results shall be discarded only after all owned terms, environments, buffers, and resource references are released.
  priority: must
  stability: stable

- id: simd_json.native_execution.cancellation_boundaries
  statement: Native work shall check cancellation before parsing, after parsing, before BEAM result construction, and before result delivery while retaining resources across any uninterruptible simdjson call.
  priority: must
  stability: evolving

- id: simd_json.native_execution.threaded_cleanup
  statement: Potentially large native teardown shall follow the accepted off-scheduler policy and shall not execute synchronously on a normal scheduler.
  priority: must
  stability: stable

- id: simd_json.native_execution.scheduler_qualification
  statement: Milestone 1 closure shall require repeatable heartbeat evidence that large concurrent valid and invalid opens and closes preserve a documented normal-scheduler latency budget without using dirty schedulers as the parse queue.
  priority: must
  stability: evolving

- id: simd_json.native_execution.preproduction_boundary
  statement: Milestone 1 documentation shall identify threaded execution as a qualification mechanism and shall not claim production admission control before Milestone 4 accepts the bounded worker pool.
  priority: must
  stability: stable

- id: simd_json.native_execution.shutdown_cleanup
  statement: Caller death, application shutdown, and NIF unload shall reject new work, retain in-flight resources to a safe cancellation boundary, suppress orphaned delivery, and release operation-owned state exactly once.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.native_execution.large_parse_responsiveness
  covers:
    - simd_json.native_execution.threaded_parse
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.scheduler_qualification
  given:
    - Independent BEAM heartbeat processes with a documented latency budget
    - Concurrent large valid and invalid JSON inputs
  when:
    - Documents are repeatedly opened and closed
  then:
    - Heartbeats continue within the qualification budget
    - Normal NIF entry latency remains bounded
    - Dirty scheduler utilization does not show JSON parsing as the general work queue

- id: simd_json.native_execution.caller_dies_while_running
  covers:
    - simd_json.native_execution.retained_resources
    - simd_json.native_execution.late_result_cleanup
    - simd_json.native_execution.cancellation_boundaries
  given:
    - A threaded document open whose caller is alive at admission
  when:
    - The caller exits while simdjson is running
  then:
    - Native input and operation resources remain valid until the next safe cancellation boundary
    - No result is delivered to another request
    - All operation-owned state is eventually released exactly once

- id: simd_json.native_execution.result_reference_mismatch
  covers:
    - simd_json.native_execution.request_correlation
    - simd_json.native_execution.late_result_cleanup
  given:
    - Two concurrent callers with distinct request references
  when:
    - Results arrive in the opposite order and a forged or stale reference is injected through a test seam
  then:
    - Each caller accepts only its own result
    - The forged or stale result cannot complete either call
    - Discarded result state is cleaned safely

- id: simd_json.native_execution.threaded_submission_failure
  covers:
    - simd_json.native_execution.no_fallback
  given:
    - A test seam that rejects threaded work submission
  when:
    - A caller opens a document
  then:
    - The call returns a structured native_failure error
    - Parsing does not run on a normal or dirty scheduler
    - Retained arguments and partial resources are released

- id: simd_json.native_execution.large_gc_teardown
  covers:
    - simd_json.native_execution.threaded_cleanup
    - simd_json.native_execution.scheduler_qualification
  given:
    - Multiple large unreachable documents
  when:
    - Garbage collection triggers their resource callbacks
  then:
    - Unbounded teardown is transferred to off-scheduler cleanup
    - Normal scheduler heartbeats remain within the qualification budget

- id: simd_json.native_execution.reload_cleanup
  covers:
    - simd_json.native_execution.retained_resources
    - simd_json.native_execution.late_result_cleanup
    - simd_json.native_execution.shutdown_cleanup
  given:
    - A test environment that supports repeated NIF load and unload
    - Queued, running, completed, and abandoned native operations
  when:
    - The application and NIF are repeatedly stopped, unloaded, and loaded
  then:
    - New work is rejected once shutdown starts
    - No completion is delivered through an unloaded or stale native generation
    - Every retained resource and operation allocation is eventually released exactly once
```

## Verification

```spec-verification
- kind: test_file
  target: test/native/threaded_admission_test.exs
  covers:
    - simd_json.native_execution.threaded_parse
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.request_correlation
    - simd_json.native_execution.retained_resources
    - simd_json.native_execution.cancellation_boundaries

- kind: test_file
  target: test/native/threaded_document_open_test.exs
  covers:
    - simd_json.native_execution.threaded_parse
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.request_correlation
    - simd_json.native_execution.retained_resources
    - simd_json.native_execution.late_result_cleanup
    - simd_json.native_execution.cancellation_boundaries
    - simd_json.native_execution.caller_dies_while_running
    - simd_json.native_execution.result_reference_mismatch

- kind: test_file
  target: test/native/threaded_teardown_test.exs
  covers:
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.cancellation_boundaries
    - simd_json.native_execution.threaded_cleanup
    - simd_json.native_execution.shutdown_cleanup
    - simd_json.native_execution.large_gc_teardown
    - simd_json.native_execution.reload_cleanup

- kind: test_file
  target: test/native/native_execution_integration_test.exs
  covers:
    - simd_json.native_execution.threaded_parse
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.threaded_cleanup
    - simd_json.native_execution.scheduler_qualification
    - simd_json.native_execution.preproduction_boundary
    - simd_json.native_execution.large_parse_responsiveness
    - simd_json.native_execution.threaded_submission_failure

- kind: source_file
  target: .spec/research/zigler_0_16_threaded_qualification.md
  covers:
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.threaded_cleanup
    - simd_json.native_execution.preproduction_boundary

- kind: source_file
  target: .spec/research/phase_4_scheduler_qualification.md
  covers:
    - simd_json.native_execution.threaded_parse
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.threaded_cleanup
    - simd_json.native_execution.scheduler_qualification
    - simd_json.native_execution.preproduction_boundary
    - simd_json.native_execution.large_parse_responsiveness

- kind: test_file
  target: test/native/document_resource_policy_test.exs
  covers:
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.threaded_cleanup

- kind: test_file
  target: test/simd_json/document_api_test.exs
  covers:
    - simd_json.native_execution.bounded_nif_entry

- kind: test_file
  target: test/simd_json/error_test.exs
  covers:
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.threaded_submission_failure

- kind: test_file
  target: test/simd_json/public_surface_test.exs
  covers:
    - simd_json.native_execution.preproduction_boundary
```

## Required Closure Evidence

Before activation, replace the bootstrap exception with executed scheduler heartbeat, request-correlation, caller-death, late-result, submission-failure, garbage-collection, application-shutdown, and NIF-unload tests. Evidence must include normal and dirty scheduler utilization plus the qualification environment and latency budget.

## Exceptions

```spec-exceptions
- id: simd_json.native_execution.milestone_01_bootstrap
  covers:
    - simd_json.native_execution.threaded_parse
    - simd_json.native_execution.bounded_nif_entry
    - simd_json.native_execution.no_fallback
    - simd_json.native_execution.request_correlation
    - simd_json.native_execution.retained_resources
    - simd_json.native_execution.late_result_cleanup
    - simd_json.native_execution.cancellation_boundaries
    - simd_json.native_execution.threaded_cleanup
    - simd_json.native_execution.scheduler_qualification
    - simd_json.native_execution.preproduction_boundary
    - simd_json.native_execution.shutdown_cleanup
    - simd_json.native_execution.large_parse_responsiveness
    - simd_json.native_execution.caller_dies_while_running
    - simd_json.native_execution.result_reference_mismatch
    - simd_json.native_execution.threaded_submission_failure
    - simd_json.native_execution.large_gc_teardown
    - simd_json.native_execution.reload_cleanup
  reason: Phase 4 now implements and integrates retained threaded construction, correlated delivery, cancellation, submission-failure containment, explicit/orphan/GC teardown, application generation cycling, and a preliminary scheduler matrix; Phase 6 must establish the final percentile budget and retain the recorded repeated shared-object unload gap until a supported harness supplies that evidence.
```
