# Phase 2 — ABI v3 and Cursor Ownership

Back to plan: [README](./README.md)

- [x] 2 Phase - Extend the private ABI to version 3 and implement an opaque,
  parent-retaining array cursor owner without executing public or threaded
  batches.

  This phase preserves every ABI v1/v2 function while freezing target, cursor,
  batch, row, status, count, byte, index, and done layouts. It registers cursor
  state and parent retention in Zig, compiles one operation-owned projection
  plan, and proves every construction failure is leak-free. Forward target and
  row traversal begin in Phase 3.

  Contract focus:

  - `simd_json.stream_cursor.private_abi_v3`
  - `simd_json.stream_cursor.opaque_cursor`
  - `simd_json.stream_cursor.parent_retention`
  - `simd_json.stream_cursor.projection_plan_reuse`
  - `simd_json.stream_cursor.exception_and_failure_cleanup`
  - `simd_json.stream_cursor.abi_v3_conformance`
  - `simd_json.native_build_and_abi.opaque_c_contract`
  - `simd_json.document_resource.parent_retention`

## 2.1 Section — Versioned Cursor and Batch ABI

- [x] 2.1 Section - Define C11-compatible ABI v3 target descriptors, cursor
  handles, batch storage, statuses, and terminal metadata.

  This section keeps C++ iterators and allocation details behind the accepted
  boundary. Every field has a fixed size, validated domain, explicit lifetime,
  and compile-time layout assertion.

  - [x] 2.1.1 Task - Add target and cursor construction descriptors.

    The task represents root/nested targets and row limits without exposing
    BEAM terms, C++ containers, references, or parser implementation types.

    - [x] 2.1.1.1 Subtask - Advance `SIMD_JSON_ABI_VERSION` to 3 while preserving all parser/document and projection-plan/execution signatures, layouts, symbol versions, and semantics.
    - [x] 2.1.1.2 Subtask - Define fixed-width target-segment and cursor-construction descriptors using existing segment tags, checked byte-arena offsets, unsigned indexes, projection-plan handle, row limit, and encoded-byte limit.
    - [x] 2.1.1.3 Subtask - Validate null/count pairs, root-path representation, segment ranges, plan ownership, zero and oversized limits, reserved fields, and every checked integer conversion before allocation.
    - [x] 2.1.1.4 Subtask - Add C11/C++17 static assertions for ABI version, target, cursor, row, batch, status, and metadata sizes, alignments, offsets, tags, and sentinels.

  - [x] 2.1.2 Task - Define bounded batch output and indexed statuses.

    The task freezes the shapes Phase 3 will populate and Phase 4 will convert
    without leaking native enum or iterator state.

    - [x] 2.1.2.1 Subtask - Define caller-owned batch storage containing checked row descriptors, existing typed scalar slots, copied-byte arena, capacities, produced counts, encoded bytes, and explicit done state.
    - [x] 2.1.2.2 Subtask - Add stable target, row, oversized-batch, cursor-state, and cancellation status categories with optional failing field slot and array-index sentinels.
    - [x] 2.1.2.3 Subtask - State exact lifetimes for borrowed input, cursor frames, plan, caller batch storage, slot string views, and copied output bytes at every ABI boundary.
    - [x] 2.1.2.4 Subtask - Reserve one `next_batch` signature that accepts a cursor, cancellation probe, bounded storage, and status output without exposing a row- or field-level call.

## 2.2 Section — Opaque Cursor Resource and Parent Retention

- [x] 2.2 Section - Construct one monotonic cursor owner that retains its
  document and compiled projection dependencies exactly once.

  This section establishes safe lifetime and state primitives independently of
  target traversal. The public API cannot obtain or inspect the resource.

  - [x] 2.2.1 Task - Implement native cursor construction and state.

    The task owns traversal frames, target descriptors, projection plan, limits,
    current row index, batch sequence, cancellation, and state behind one
    opaque handle.

    - [x] 2.2.1.1 Subtask - Add an opaque cursor constructor and null-safe destructor with `ready`, `running`, `done`, `cancelled`, and `closed` transitions and one atomic running winner.
    - [x] 2.2.1.2 Subtask - Copy retained target-key bytes and hold or transfer exactly one owned projection plan without storing raw BEAM terms in C++.
    - [x] 2.2.1.3 Subtask - Reject repeated running, cancelled, done, and closed transitions without parser access or state regression.
    - [x] 2.2.1.4 Subtask - Add bounded test-only state, frame, plan, key-byte, cursor, and parent-retention accounting absent from release symbols and strings.

  - [x] 2.2.2 Task - Retain and release the parent graph safely.

    The task applies the Milestone 1 resource graph to the new child and proves
    no cursor holds an unowned document pointer.

    - [x] 2.2.2.1 Subtask - Register a private Zig cursor resource whose owner uses the BEAM resource API to retain the genuine parent document control before any native handle can dereference it.
    - [x] 2.2.2.2 Subtask - Validate owner and generation before construction, record the generation in cursor state, and reject stale parent access without revealing native identity.
    - [x] 2.2.2.3 Subtask - Release cursor-owned plan and traversal state before releasing the retained parent, allowing the existing document cleanup order to destroy document, parser, and input afterward.
    - [x] 2.2.2.4 Subtask - Inject failure after every target copy, plan acquisition, resource allocation, parent retention, and cursor construction step and require reverse baseline recovery.

## 2.3 Section — Zig Ownership, Build, and Release Boundary

- [x] 2.3 Section - Import ABI v3 through the canonical header and update the
  package and symbol policy without creating a public cursor path.

  This section makes Zig the explicit owner of descriptor and resource
  lifetimes and ensures the ABI change invalidates stale qualification.

  - [x] 2.3.1 Task - Add owned Zig descriptors and cursor wrappers.

    The task converts only Phase 1 normalized data and gives every allocation
    one idempotent cleanup path.

    - [x] 2.3.1.1 Subtask - Import the canonical header with `@cImport` and assert every ABI v3 target, cursor, batch, row, status, index, byte, and done layout against Zig.
    - [x] 2.3.1.2 Subtask - Serialize normalized target bytes and limits with checked sizes and acquire the existing projection plan through one owned wrapper.
    - [x] 2.3.1.3 Subtask - Add an owned cursor wrapper whose `deinit` clears its handle, closes idempotently, releases descriptors, plan and parent in dependency order, and never frees C-owned memory directly.
    - [x] 2.3.1.4 Subtask - Keep batch execution unavailable from Elixir and limit Phase 2 smoke behavior to construction, state, retention, and destruction conformance.

  - [x] 2.3.2 Task - Update native package and release policy.

    The task makes every new source and symbol reviewable without disturbing
    the earlier public and native surfaces.

    - [x] 2.3.2.1 Subtask - Add cursor headers, sources, Zig owners, harnesses, plan documents, and tests to package inventory, native manifest, provenance coverage, and qualification fingerprint inputs.
    - [x] 2.3.2.2 Subtask - Extend the independently linked C ABI allowlist only with accepted cursor constructor, destructor, and next-batch symbols while retaining earlier symbol versions.
    - [x] 2.3.2.3 Subtask - Prove the release NIF still exports only `nif_init` and no cursor, target, row, batch, status, pointer, counter, failure control, or test string reaches an Elixir export.

## 2.4 Section — Phase 2 Integration Tests

- [x] 2.4 Section - Prove ABI v3 layout, cursor state, plan and parent
  ownership, failure containment, Zig cleanup, package contents, and release
  visibility independently of array traversal.

  This section freezes the only safe cursor construction boundary Phase 3 may
  advance.

  - [x] 2.4.1 Task - Run independent C ABI cursor conformance.

    The task uses C11 and C++17 harnesses without Zig or Elixir assumptions.

    - [x] 2.4.1.1 Subtask - Compile the canonical header in both languages and assert every ABI v1/v2 regression plus exact ABI v3 version, signature, layout, tag, sentinel, limit, and ownership rule.
    - [x] 2.4.1.2 Subtask - Construct root, nested, empty-target, deep, Unicode, maximum-index, minimum/maximum-limit, large-projection, and repeated-state cursors and inspect only bounded summaries.
    - [x] 2.4.1.3 Subtask - Submit invalid handles, pointer/count pairs, tags, ranges, reserved fields, plan state, generations, limits, and every injected exception/allocation failure; require stable status and baseline recovery.
    - [x] 2.4.1.4 Subtask - Destroy null, partial, cancelled, done, closed, and caller-cleared cursor handles under AddressSanitizer and UndefinedBehaviorSanitizer.

  - [x] 2.4.2 Task - Run Zig retention and release gates.

    The task passes real Phase 1 normalized fixtures through Zig serialization
    and the ABI while preserving every existing library behavior.

    - [x] 2.4.2.1 Subtask - Compare deterministic target/plan/cursor summaries and prove caller keys, owner PID, source bytes, raw BEAM terms, and resource pointers never enter the C ABI unexpectedly.
    - [x] 2.4.2.2 Subtask - Drop all other parent terms, exercise parent-retention accounting and reverse destruction, and run ordinary and sanitizer Zig cursor ownership tests.
    - [x] 2.4.2.3 Subtask - Inspect package inventory, release symbols and strings, and run ABI v1/v2, document-resource, projection-plan, and projection-engine regressions unchanged under ABI v3.
    - [x] 2.4.2.4 Subtask - Run focused ABI/cursor tests, `mix test`, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 2 complete.
