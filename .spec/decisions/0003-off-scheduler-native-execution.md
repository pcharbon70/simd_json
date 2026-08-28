---
id: simd_json.off_scheduler_native_execution
status: accepted
date: 2026-08-27
affects:
  - simd_json.native_execution
  - simd_json.document_resource
  - simd_json.document_api
---

# Off-Scheduler Native Execution

## Context

Parsing cost grows with input size and cannot be bounded tightly enough for an ordinary NIF. Running it on a normal BEAM scheduler would delay unrelated processes and can make the VM unresponsive. Sending every large parse to dirty CPU schedulers would protect normal schedulers but turn a limited VM-wide facility into the library's JSON work queue.

Milestone 4 will introduce the final fixed native worker pool, cancellation registry, backpressure, and telemetry. Milestone 1 still needs a safe execution boundary that proves the native stack without pre-implementing the entire production runtime.

## Decision

Milestone 1 parsing and explicit potentially large cleanup run through the
pinned Zigler release's threaded execution facility. They never run as
ordinary synchronous NIF work and never use dirty CPU schedulers as the
default parse queue. A library-owned coordinator, rather than the requesting
process, owns each generated Zigler thread resource through completion and
join. This contains the pinned implementation's 750-microsecond destructor
join limit when a requesting process dies.

The ordinary NIF portion is restricted to bounded work:

- validate small argument shapes and resource types;
- retain required BEAM resources;
- create or validate a unique request reference;
- submit threaded work;
- perform bounded lifecycle-state transitions;
- marshal or receive already-bounded result metadata.

The Elixir wrapper presents a synchronous tagged-result API while the calling process waits for the matching threaded result. Every request is correlated by an unforgeable reference. A late, duplicate, mismatched, timed-out, or caller-orphaned result is discarded only after its native allocations and retained resources are released.

Milestone 1 is a qualification runtime, not the production concurrency design. Its documentation must state that production admission control depends on Milestone 4. No code may silently fall back to an ordinary or dirty NIF when threaded submission fails.

### Cancellation and teardown

Caller death, explicit close, application shutdown, and NIF unload mark work cancelled when the accepted Zigler/native boundary can do so safely. Native code checks cancellation before parsing, after parsing, before BEAM result construction, and before delivery. If the underlying simdjson call is not interruptible, the resource remains retained until that call reaches the next safe boundary.

Potentially large destruction is executed through the same off-scheduler policy. Ordinary resource callbacks may atomically detach or enqueue cleanup, but may not synchronously destroy unbounded parser or buffer state on a normal scheduler.

The pinned Zigler launcher is not legal from resource callback context. GC and
orphan teardown therefore transfer an intrusive cleanup record to one
module-owned, cleanup-only native dispatcher that is started at load and
drained before unload. This narrow dispatcher may destroy detached state but
may never parse, admit public work, or become the production work queue. It is
the required callback-safe handoff, not a fallback to an ordinary or dirty
scheduler and not the bounded parse pool assigned to Milestone 4.

The exact permitted environment, term, resource, message, callback, and join
operations—and the reason for this cleanup exception—are recorded in
[`zigler_0_16_threaded_qualification.md`](../research/zigler_0_16_threaded_qualification.md).

### Phase 3 implementation checkpoint

The registered resource destructor now performs only the bounded atomic
close-detach transition. No production NIF can copy input, call simdjson, or
place parsed state in the resource, and static policy tests freeze that boundary.
The off-scheduler parse and cleanup executors remain intentionally absent until
Phase 4; this checkpoint is a prerequisite for the decision, not a scheduling
substitute or policy change.

### Phase 4 threaded qualification checkpoint

Inspection and smoke execution against Zigler `0.16.0` confirm that admission
and join are ordinary NIF entries, parser work runs with the threaded context,
and a private environment plus retained operation resource can preserve input
without an input-sized admission copy. The generated destructor's documented
join timeout and its inability to launch work from callback context require
the stable coordinator and cleanup-only dispatcher above. This amendment
closes the explicit reconciliation required before parsed resources become
reachable; it does not permit another execution fallback.

The reconciled path is now implemented. Generated Zigler workers have a stable
coordinator owner, while document resource callbacks detach an intrusive
control block into the cleanup-only dispatcher without allocating, waiting, or
destroying native state. Rejected callback handoff retains that same block on a
retry list. Application stop cancels and drains coordinated operations before
invalidating admission; NIF unload rejects admission, drains dispatcher work,
joins its thread, and only then frees module state. OTP 27.3 application
stop/start is executed, while repeated shared-object unload remains explicitly
unqualified as recorded in the pinned qualification note.

### Scheduler qualification

Milestone 1 must include a repeatable scheduler-responsiveness test. Independent BEAM heartbeat processes run while large valid and invalid documents are opened and closed concurrently. The test records normal and dirty scheduler utilization and fails against a documented latency budget selected for the qualification environment. Phase 4's preliminary profile and regression thresholds are recorded in [`phase_4_scheduler_qualification.md`](../research/phase_4_scheduler_qualification.md); Phase 6 owns the formal supported-target percentile budget.

Native throughput alone cannot close the milestone. The evidence must show that unrelated BEAM work continues making progress and that dirty schedulers are not the hidden execution pool.

## Consequences

The first native vertical slice protects normal and dirty schedulers while keeping the final worker-pool design deferred to its owning milestone. Request correlation, cancellation-safe resource retention, and deferred cleanup are established early enough for later APIs to reuse.

Threaded execution may have weaker admission control and observability than the Milestone 4 pool. The Milestone 1 API must therefore remain explicitly pre-production, and performance results cannot be generalized to final concurrency behavior.

The implementation must test result and cleanup races that a purely synchronous NIF would not have.

## Alternatives Rejected

- **Ordinary synchronous NIF parsing:** input-dependent work can monopolize a normal scheduler.
- **Dirty CPU NIF parsing for every document:** this turns limited dirty schedulers into an implicit JSON pool and couples this library's load to unrelated native work.
- **Caller-owned unmanaged OS thread per call:** this has no stable join owner
  when the caller dies and no safe application-unload protocol. The temporary
  Zigler qualification path is instead owned and drained by the internal
  coordinator and remains explicitly pre-production.
- **Implement the final worker pool in Milestone 1:** that expands the foundation milestone into Milestone 4 and delays validation of the ownership and ABI boundaries.
- **Return before native ownership is secured:** caller death or garbage collection could invalidate data still used by the native thread.

## Reopening Conditions

This decision is intentionally superseded for production scheduling when Milestone 4 accepts a fixed native worker pool with bounded admission, cancellation, backpressure, telemetry, and shutdown evidence. Any interim execution replacement must continue to exclude input-dependent work and unbounded teardown from normal schedulers and must not consume dirty schedulers as its general queue.
