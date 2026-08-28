# Phase 3 — Zig Resource and Padded Input Ownership

Back to plan: [README](./README.md)

- [x] 3 Phase - Build the native ownership graph that keeps simdjson state and padded input valid for exactly one opaque document lifetime.

  This phase imports the proven C ABI into Zig, implements the always-copy input
  policy, registers the opaque BEAM resource type, and defines lifecycle and
  reverse-destruction primitives. It deliberately does not expose a production
  parse NIF: input-dependent copying and parsing are connected to Zigler's
  threaded execution only in Phase 4.

  Contract focus:

  - `simd_json.document_resource.opaque_handle`
  - `simd_json.document_resource.padded_owned_copy`
  - `simd_json.document_resource.zero_copy_disabled`
  - `simd_json.document_resource.complete_ownership`
  - `simd_json.document_resource.lifecycle`
  - `simd_json.document_resource.reverse_destruction`
  - `simd_json.document_resource.parent_retention`
  - `simd_json.document_resource.test_accounting`
  - `simd_json.document_resource.input_lifetime`
  - `simd_json.document_resource.partial_open_failure`

## 3.1 Section — Zig C Interop and Resource Registration

- [x] 3.1 Section - Import the private C contract without widening it and register one opaque BEAM document resource.

  This section makes Zig the sole owner of BEAM-specific state and native term
  marshalling. C++ remains inaccessible above the imported C header, and the
  initial resource registration performs only bounded setup.

  - [x] 3.1.1 Task - Add typed Zig declarations and status adaptation.

    The task mirrors the fixed C layouts at compile time and creates a native
    adapter that does not yet construct public BEAM errors.

    - [x] 3.1.1.1 Subtask - Import or declare every C ABI type and function from the canonical header without duplicating numeric constants by hand.
    - [x] 3.1.1.2 Subtask - Add compile-time size, alignment, signedness, and status-value assertions between Zig and the C header.
    - [x] 3.1.1.3 Subtask - Represent native success, known parser failures, allocation failure, invalid arguments, and unknown failure as a closed Zig error/status union.
    - [x] 3.1.1.4 Subtask - Keep raw C handles private to the native module and prohibit them from being encoded as integers, binaries, or public terms.

  - [x] 3.1.2 Task - Register the opaque document resource type.

    The task defines one resource identity shared by every later open, close,
    projection, and child-resource operation without exposing resource internals
    to Elixir.

    - [x] 3.1.2.1 Subtask - Register the document resource at NIF load with explicit load, upgrade, unload, and destructor behavior for the pinned OTP/Zigler versions.
    - [x] 3.1.2.2 Subtask - Define native resource storage for padded input, logical length, parser/document handles, owner PID, lifecycle state, generation, admitted-operation state, and bounded synchronization.
    - [x] 3.1.2.3 Subtask - Initialize resource memory to a destructible empty state before any fallible field construction begins.
    - [x] 3.1.2.4 Subtask - Add private retain/release helpers that future child resources must use to keep their parent document alive; add no cursor or child API in this milestone.

## 3.2 Section — Aligned Padded Input

- [x] 3.2 Section - Copy every accepted binary into one aligned native allocation with exact initialized padding.

  This section removes all ambiguity about BEAM binary padding and lifetime. The
  logical JSON length remains separate from allocation capacity so parser input,
  byte offsets, counters, and diagnostics never include padding bytes.

  - [x] 3.2.1 Task - Implement overflow-safe padded allocation and copying.

    The task owns the only Milestone 1 path from caller bytes to simdjson-readable
    native memory.

    - [x] 3.2.1.1 Subtask - Compute `logical_length + required_padding` with checked arithmetic and reject lengths that overflow the C ABI, Zig allocator, or BEAM-facing size representation.
    - [x] 3.2.1.2 Subtask - Allocate with the exact alignment required by the pinned simdjson release and store both logical length and allocation capacity.
    - [x] 3.2.1.3 Subtask - Copy exactly the logical input bytes once and initialize every required padding byte according to the pinned API contract.
    - [x] 3.2.1.4 Subtask - Pass only logical length to the C ABI and keep capacity and padding private to cleanup and native safety checks.
    - [x] 3.2.1.5 Subtask - On any later construction failure, release the padded allocation through the same allocator and clear its resource fields before returning.

  - [x] 3.2.2 Task - Make the zero-copy exclusion executable.

    The task prevents a future optimization or helper from accidentally passing
    arbitrary BEAM memory directly to simdjson during Milestone 1.

    - [x] 3.2.2.1 Subtask - Centralize parser input creation behind the owned-padded-copy helper with no alternate borrowed-binary branch.
    - [x] 3.2.2.2 Subtask - Add a compile-time or structural test proving the resource's parser pointer lies within its owned native allocation, not the original BEAM binary.
    - [x] 3.2.2.3 Subtask - Add guard-page native tests that place the logical end at boundary-sensitive positions and prove no access occurs beyond the initialized padding capacity.

## 3.3 Section — Lifecycle and Exactly-Once Cleanup Primitives

- [x] 3.3 Section - Define monotonic resource state and one dependency-safe cleanup operation before scheduling is attached.

  This section separates cleanup correctness from where cleanup runs. Phase 3
  proves the state machine and destruction order natively; Phase 4 supplies the
  off-scheduler executor required for production parse and teardown.

  - [x] 3.3.1 Task - Implement the document lifecycle state machine.

    The task ensures concurrent close, failure, GC, and shutdown paths can
    converge without double ownership or resurrection.

    - [x] 3.3.1.1 Subtask - Represent the only lifecycle progression as `open → closing → closed` and prevent backward or skipped publication of usable state.
    - [x] 3.3.1.2 Subtask - Use one atomic compare-and-transition so exactly one caller becomes cleanup owner and all other close paths observe or join the same operation.
    - [x] 3.3.1.3 Subtask - Increment or invalidate the generation when closing starts so future retained children cannot use stale parser state.
    - [x] 3.3.1.4 Subtask - Define bounded admission bookkeeping so close can prevent new operations and determine when already-admitted native work is safe to release.

  - [x] 3.3.2 Task - Implement reverse destruction and partial-open rollback.

    The task creates one idempotence guard around the actual release sequence and
    uses the same sequence for explicit close, GC, construction failure, caller
    loss, and unload.

    - [x] 3.3.2.1 Subtask - Prevent new work and invalidate the active generation before destroying native parser state.
    - [x] 3.3.2.2 Subtask - Destroy the On-Demand document before its parser, release the padded buffer afterward, and clear each field as its ownership ends.
    - [x] 3.3.2.3 Subtask - Route failure after every allocation or handle-construction step through dependency-safe rollback with no usable resource publication.
    - [x] 3.3.2.4 Subtask - Keep the resource destructor bounded to atomic detach/enqueue preparation; do not run potentially large destruction on a normal scheduler.

  - [x] 3.3.3 Task - Add bounded test-only resource accounting.

    The task supplies enough observability to prove baseline recovery and
    exactly-once behavior without exposing pointers, input bytes, or unbounded
    per-document data.

    - [x] 3.3.3.1 Subtask - Count live padded buffers, parser handles, document handles, resource records, retained parents, admitted operations, and completed destruction events in test builds.
    - [x] 3.3.3.2 Subtask - Provide a bounded snapshot and quiescence wait usable only by tests, with no native addresses, allocation contents, or caller JSON.
    - [x] 3.3.3.3 Subtask - Compile accounting entrypoints and failure injection out of the release artifact and verify their absence by symbol inspection.

## 3.4 Section — Phase 3 Integration Tests

- [x] 3.4 Section - Prove the Zig, C ABI, padded-memory, and resource-lifecycle layers compose without scheduler-unsafe parsing.

  This section validates the ownership foundation through native tests and only
  bounded BEAM resource-registration smoke checks. Production open remains
  unavailable until Phase 4 supplies threaded admission.

  - [x] 3.4.1 Task - Run padded-input and cross-language ownership tests.

    The task proves the Zig allocation is the memory parsed by C++ and remains
    valid independently of the source binary.

    - [x] 3.4.1.1 Subtask - Exercise zero-length, small, alignment-boundary, padding-boundary, and overflow-length cases through Zig into the C ABI.
    - [x] 3.4.1.2 Subtask - Release or overwrite the source test buffer after copying and prove the native document continues reading only its owned padded allocation.
    - [x] 3.4.1.3 Subtask - Verify logical byte offsets never include initialized padding and guard-page tests remain clean under AddressSanitizer and UndefinedBehaviorSanitizer.
    - [x] 3.4.1.4 Subtask - Assert no borrowed or zero-copy parser-input path is reachable in the Milestone 1 native build.

  - [x] 3.4.2 Task - Run resource rollback and destruction-order tests.

    The task executes `partial_open_failure` and the lifecycle primitives across
    every construction edge before asynchronous scheduling adds more races.

    - [x] 3.4.2.1 Subtask - Inject failure after buffer allocation, parser creation, document creation, resource initialization, and immediately before resource publication.
    - [x] 3.4.2.2 Subtask - Assert each case releases completed allocations in reverse order, publishes no usable resource, and returns all test counters to baseline.
    - [x] 3.4.2.3 Subtask - Race native lifecycle transitions and prove one cleanup winner, monotonic state, one generation invalidation, and one destruction event per owned object.
    - [x] 3.4.2.4 Subtask - Load the NIF, register and release a bounded empty resource fixture, and confirm ordinary NIF callbacks perform no input-dependent copy, parse, or large teardown.
    - [x] 3.4.2.5 Subtask - Run the focused native/resource tests, `mix test`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 3 complete.
