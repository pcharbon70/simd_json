# Phase 2 — ABI v2 and Native Projection Plan

Back to plan: [README](./README.md)

- [ ] 2 Phase - Extend the exception-safe private C boundary and compile the
  validated projection into an operation-owned prefix-sharing native plan.

  This phase advances the private ABI to version 2 without changing Milestone 1
  parser/document behavior. It defines fixed descriptors and statuses, builds
  and destroys the opaque plan, imports the contract into Zig, and proves every
  construction failure is leak-free. Execution is limited to plan conformance;
  document traversal begins in Phase 3.

  Contract focus:

  - `simd_json.projection_engine.prefix_sharing_plan`
  - `simd_json.projection_engine.private_abi_v2`
  - `simd_json.projection_engine.exception_and_failure_cleanup`
  - `simd_json.projection_engine.abi_v2_conformance`
  - `simd_json.native_build_and_abi.opaque_c_contract`
  - `simd_json.native_build_and_abi.exception_containment`
  - `simd_json.native_build_and_abi.partial_failure_cleanup`
  - `simd_json.native_build_and_abi.symbol_visibility`

## 2.1 Section — Versioned Projection ABI Contract

- [ ] 2.1 Section - Define C11-compatible projection descriptors, values,
  statuses, and opaque ownership for private ABI version 2.

  This section keeps C++ layouts and exceptions behind the existing boundary.
  Every cross-language field has a fixed size, explicit lifetime, validated
  range, and compile-time layout assertion.

  - [ ] 2.1.1 Task - Add normalized projection input descriptors.

    The task represents output slots and typed path segments without exposing
    BEAM terms, C++ strings, templates, containers, or references.

    - [ ] 2.1.1.1 Subtask - Advance `SIMD_JSON_ABI_VERSION` to 2 and retain the four Milestone 1 parser/document function signatures and semantics unchanged.
    - [ ] 2.1.1.2 Subtask - Define fixed-width projection-entry and segment descriptors using explicit tags, slot indexes, byte-arena offsets and lengths, and unsigned array indexes.
    - [ ] 2.1.1.3 Subtask - Validate descriptor counts, pointer/count pairs, byte ranges, integer overflow, tag values, path non-emptiness, and slot bounds before allocation or dereference.
    - [ ] 2.1.1.4 Subtask - Add C11/C++17 static assertions for every descriptor, status, and result-slot size and offset consumed by Zig.

  - [ ] 2.1.2 Task - Add stable projection statuses and typed result slots.

    The task defines the native vocabulary Phase 3 will populate and Phase 5
    will translate without leaking simdjson enum values.

    - [ ] 2.1.2.1 Subtask - Add stable status categories for missing field, index out of bounds, incorrect type, number out of range, consumed cursor, and cancellation while preserving existing parse and internal categories.
    - [ ] 2.1.2.2 Subtask - Extend status metadata with an optional failing output-slot sentinel while keeping logical byte offsets distinct from padding and native codes diagnostic-only.
    - [ ] 2.1.2.3 Subtask - Define a fixed-layout tagged result slot for signed integer, unsigned integer, floating point, boolean, null, and borrowed string pointer/length values.
    - [ ] 2.1.2.4 Subtask - State and test that string pointers and result slots are valid only while the executing document and operation-owned slot storage remain alive.

## 2.2 Section — Opaque Prefix-Sharing Plan Ownership

- [ ] 2.2 Section - Construct and destroy one immutable native plan from the
  complete normalized descriptor set.

  This section owns plan nodes and copied object-key bytes in C++. The plan is a
  private operation detail with no public resource or cross-call cache.

  - [ ] 2.2.1 Task - Build the projection tree deterministically.

    The task inserts every typed path into one trie while separating caller slot
    order from future source-order traversal.

    - [ ] 2.2.1.1 Subtask - Add an opaque `simd_json_projection_plan` constructor that copies every retained object-key byte and creates typed object and array edges.
    - [ ] 2.2.1.2 Subtask - Merge common prefixes and store multiple terminal slot indexes for identical paths with distinct output keys.
    - [ ] 2.2.1.3 Subtask - Canonicalize object edges for deterministic matching and array edges in ascending numeric order without changing output-slot association.
    - [ ] 2.2.1.4 Subtask - Reject structurally inconsistent normalized descriptors as invalid arguments even though Phase 1 normally prevents them.

  - [ ] 2.2.2 Task - Implement exactly-once plan cleanup.

    The task applies the existing constructor/destructor discipline to every
    node, key copy, terminal list, and auxiliary index.

    - [ ] 2.2.2.1 Subtask - Add a null-safe plan destructor and one reverse-order cleanup helper used by ordinary destruction and all partial-construction failures.
    - [ ] 2.2.2.2 Subtask - Inject allocation failure after every plan construction edge and assert each completed allocation is released exactly once.
    - [ ] 2.2.2.3 Subtask - Catch known, allocation, standard, and unknown C++ exceptions and map them to stable statuses without exposing exception text.
    - [ ] 2.2.2.4 Subtask - Add bounded test-only node, key-byte, and plan accounting that is absent from release symbols and strings.

## 2.3 Section — Zig Ownership and Release Boundary

- [ ] 2.3 Section - Import ABI v2 into Zig and enforce plan lifetime and symbol
  policy above the C++ shim.

  This section proves the canonical header is the single source of layout truth
  and prepares an operation-owned plan wrapper for threaded traversal.

  - [ ] 2.3.1 Task - Serialize normalized projections for the C ABI.

    The task converts the private Phase 1 representation into bounded native
    arenas and descriptors without interpreting arbitrary terms in C++.

    - [ ] 2.3.1.1 Subtask - Import the canonical header through Zig `@cImport` and add compile-time assertions matching every ABI v2 tag, sentinel, size, and offset.
    - [ ] 2.3.1.2 Subtask - Serialize validated paths into one operation-owned key-byte arena and fixed descriptor arrays with checked length and offset conversion.
    - [ ] 2.3.1.3 Subtask - Wrap plan construction in an owned Zig type whose `deinit` is idempotent and whose error path releases descriptors and arena bytes after the C plan has copied what it retains.

  - [ ] 2.3.2 Task - Update native build and symbol policy.

    The task makes the ABI extension explicit in manifests, conformance builds,
    release inspection, and qualification invalidation.

    - [ ] 2.3.2.1 Subtask - Add the projection translation units and headers to the pinned native build manifest, package inventory, license/provenance coverage, and qualification fingerprint inputs.
    - [ ] 2.3.2.2 Subtask - Extend the independently linked C ABI allowlist only with the accepted plan constructor, plan destructor, and future execution symbol; keep all C++ and test hooks hidden.
    - [ ] 2.3.2.3 Subtask - Prove release NIF linkage still exports only its initialization entry and no plan, descriptor, result pointer, or test diagnostic reaches an Elixir export.

## 2.4 Section — Phase 2 Integration Tests

- [ ] 2.4 Section - Prove ABI v2 layout, plan topology, failure containment,
  Zig ownership, and release visibility independently of BEAM traversal.

  This section freezes the safe native plan boundary Phase 3 is allowed to
  execute.

  - [ ] 2.4.1 Task - Run independent C ABI plan conformance.

    The task exercises the public private header from C11 ordinary and sanitizer
    harnesses without relying on Zig or Elixir implementation details.

    - [ ] 2.4.1.1 Subtask - Compile the header as C11 and C++17 and assert version, tag, sentinel, status, descriptor, slot, and function signatures exactly.
    - [ ] 2.4.1.2 Subtask - Construct empty-invalid, single-path, shared-prefix, identical-path, deep-object, deep-array, Unicode-key, maximum-index, and large valid plans and inspect only bounded test summaries.
    - [ ] 2.4.1.3 Subtask - Submit null pointers, invalid counts, overflowing byte ranges, invalid tags, duplicate slot ids, and injected exceptions/allocation failures; assert stable statuses and baseline recovery.
    - [ ] 2.4.1.4 Subtask - Destroy null, partial, complete, and already-cleared caller handles under AddressSanitizer and UndefinedBehaviorSanitizer.

  - [ ] 2.4.2 Task - Run Zig integration and release gates.

    The task sends real Phase 1 normalized fixtures through Zig serialization
    and the C++ plan boundary while preserving the Milestone 1 build.

    - [ ] 2.4.2.1 Subtask - Round-trip normalized descriptors, compare deterministic plan summaries, and prove caller keys and raw BEAM terms never enter the C ABI.
    - [ ] 2.4.2.2 Subtask - Run ordinary and sanitizer Zig ownership tests across every construction and cleanup edge and require all plan/arena counters at baseline.
    - [ ] 2.4.2.3 Subtask - Inspect release symbols and strings, run the existing C ABI and resource regression suites, and prove all Milestone 1 constructor/destructor behavior remains unchanged under ABI v2.
    - [ ] 2.4.2.4 Subtask - Run focused ABI/plan tests, `mix test`, `mix format --check-formatted`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 2 complete.
