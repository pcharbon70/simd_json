# SimdJson Package

Milestone 4 Phase 4 adds internal monitored fixture delivery and resource
serialization without public modules, functions, dependencies, or
configuration keys.

Milestone 3 Phase 6 adds the active streaming modules, ABI v3 cursor sources,
operations and acceptance guides, qualification scripts, frozen compressed ETL
fixtures, and their generator/policy to the source package and qualification
fingerprint. Generated native artifacts remain excluded.

Current package and documentation contract for the `SimdJson` library.

The package distributes the pinned native build inputs, private C ABI, C++
shim, Zig ownership/resource sources, symbol policy, native conformance
harnesses, correlated threaded operation runtime, stable coordinator, and
cleanup-only dispatcher. Its active Milestone 1 and 2 surface provides binary
`open/1`, owner-safe `close/1`, binary/document `select/2`, an opaque document,
and a closed redacted error vocabulary.
Phase 6 Section 6.1 also makes the Hex archive buildable with explicit package
metadata, excludes generated Zigler intermediates, and inspects the unpacked
artifact for every required native source, header, provenance, and license.
Milestone 2 is defined by three accepted projection ADRs, three active subjects
without exceptions, and a completed six-phase implementation plan. Phase 1
packages an undocumented internal projection validator and
extends the common error representation with reserved projection reasons and
an optional redacted path. Phase 2 packages ABI v2 descriptors, the opaque
C++ prefix-sharing plan, its Zig serializer/owner, independent conformance
harnesses, and the expanded private shared-ABI allowlist. Phase 3 now packages
the C++-only document/traversal coordination header, complete C guided-engine
corpus, and Zig typed-slot/cancellation cases alongside the still-private
execution engine. Phase 4 packages the private projection operation adapter,
correlated threaded worker, one-shot document reservation, worker-local binary
document graph, join-time map copy, bounded diagnostics/accounting, and focused
threading/lifetime/teardown integration matrices. Phase 5 publishes the narrow
typed `SimdJson.select/2` boundary for binary and genuine document sources,
stable exact-key scalar maps and path errors, one-shot lifecycle documentation,
doctests, and locked export/type/protocol allowlists. The NIF still exports only
`nif_init`, all native projection modules and plans remain undocumented and
operation-scoped, and eager decode, streaming, cursors, transfer, raw handles,
compiled plans, JSONPath, defaults, and container materialization remain
absent. Phase 6 packages frozen sparse fixtures and policy, a direct exact Jason
development/test pin, release/runtime/benchmark qualification commands, and
operations/acceptance records. The active subjects bind their complete claims
to executed commands on the qualified target.
Milestone 3 is defined by three accepted streaming ADRs, three planned subjects
with complete bootstrap exceptions, and a six-phase batched-array-streaming
implementation plan. Phase 1 now packages an undocumented opaque stream-option
normalizer, reuses the projection validator for target and field paths, and
extends the shared error representation with a reserved batch reason and
optional redacted array index. The root module still exports only the active
Milestone 1 and 2 operations. Phase 2 now packages private ABI v3 target,
cursor, row, batch, status, C++ owner, Zig owner/resource, symbol policy, and
independent ordinary/sanitizer harnesses. The NIF still exports only `nif_init`;
Phase 5 adds only `stream/2`, the opaque `SimdJson.Stream` type, its Enumerable
and redacted Inspect implementations, and the Milestone 3 guide. Native cursor,
batch, diagnostic, and failure-control surfaces remain private.
Phase 3 packages the forward-only native batch engine and its expanded C/Zig
qualification corpus. The shell-backed ExUnit gates retain explicit bounded
timeouts sized for clean CI compilation of that larger private native surface.
Phase 4 packages private correlated setup/batch operations, binary and document
cursor graphs, shared select/stream one-shot reservation, exact demand
sequencing, copied bounded row lists, cancellation, and compile-time-gated
lifecycle accounting. The root exports remain unchanged and no Enumerable,
cursor, batch, diagnostic, or production-pool API is public.

Milestone 4 Phase 1 adds the accepted pool configuration decision, planned
native-pool subject, and ordered implementation plan to the package-local Spec
Led layout. No public pool configuration module or production execution claim
is added to package documentation in this phase.

```spec-meta
id: simd_json.package
kind: package
status: active
summary: Active native foundation and projection library with a public pre-production Milestone 3 lazy streaming surface pending Phase 6 qualification.
surface:
  - .tool-versions
  - README.md
  - mix.exs
  - mix.lock
  - lib/**/*.ex
  - native/manifest.exs
  - native/README.md
  - native/vendor/simdjson/**
  - test/**/*.exs
  - docs/milestones/*.md
  - .spec/decisions/*.md
  - .spec/planning/**/*.md
  - .spec/specs/*.spec.md
  - .spec/research/*.md
```

## Requirements

```spec-requirements
- id: simd_json.package.mix_library
  statement: The repository shall define the :simd_json Mix library with a SimdJson root module and an ExUnit test suite.
  priority: must
  stability: evolving

- id: simd_json.package.specled_tooling
  statement: The Mix project shall include SpecLedEx as a commit-pinned development and test dependency that is excluded from runtime releases.
  priority: must
  stability: evolving

- id: simd_json.package.native_build_tooling
  statement: The Mix project shall pin Zigler as a compile-time-only dependency and shall record compatible BEAM, Zig, C++, simdjson, build-profile, and target inputs in the repository native manifest.
  priority: must
  stability: evolving

- id: simd_json.package.native_source_distribution
  statement: Hex package metadata shall include the exact vendored simdjson source, provenance manifest, patch declaration, and upstream license files required for an offline consumer build.
  priority: must
  stability: stable

- id: simd_json.package.documentation_layout
  statement: Architecture research shall live under .spec/research, while actionable wrapper milestone documents shall live under docs/milestones and reference the supporting research.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: mix.exs
  covers:
    - simd_json.package.mix_library
    - simd_json.package.specled_tooling
    - simd_json.package.native_build_tooling
    - simd_json.package.native_source_distribution

- kind: source_file
  target: .tool-versions
  covers:
    - simd_json.package.native_build_tooling

- kind: source_file
  target: native/manifest.exs
  covers:
    - simd_json.package.native_build_tooling

- kind: source_file
  target: native/README.md
  covers:
    - simd_json.package.native_build_tooling

- kind: source_file
  target: native/vendor/simdjson/README.md
  covers:
    - simd_json.package.native_source_distribution

- kind: command
  target: mix simd_json.verify_vendor
  covers:
    - simd_json.package.native_source_distribution

- kind: test_file
  target: test/native/native_build_policy_test.exs
  covers:
    - simd_json.package.native_source_distribution

- kind: test_file
  target: test/native/document_resource_policy_test.exs
  covers:
    - simd_json.package.native_build_tooling

- kind: source_file
  target: lib/simd_json.ex
  covers:
    - simd_json.package.mix_library

- kind: source_file
  target: docs/milestones/README.md
  covers:
    - simd_json.package.documentation_layout

- kind: source_file
  target: docs/milestones/02-projection-api.md
  covers:
    - simd_json.package.documentation_layout

- kind: source_file
  target: .spec/planning/milestone_02_projection_api/README.md
  covers:
    - simd_json.package.documentation_layout

- kind: source_file
  target: .spec/planning/milestone_03_batched_array_streaming/README.md
  covers:
    - simd_json.package.documentation_layout

- kind: source_file
  target: .spec/research/simdjson_beam_nif_architecture.md
  covers:
    - simd_json.package.documentation_layout

- kind: source_file
  target: .spec/research/zigler_0_16_threaded_qualification.md
  covers:
    - simd_json.package.documentation_layout

- kind: command
  target: mix test
  covers:
    - simd_json.package.mix_library

- kind: command
  target: bash scripts/ci/qualify_native_release.sh
  covers:
    - simd_json.package.native_build_tooling
    - simd_json.package.native_source_distribution
```
