# SimdJson Package

Current package and documentation contract for the `SimdJson` library.

The package currently distributes the pinned native build inputs, private C
ABI, C++ shim, Zig ownership/resource sources, symbol policy, native
conformance harnesses, and Phase 4's internal correlated threaded operation
runtime, stable coordinator, and cleanup-only dispatcher. Phase 5 adds the
narrow binary `open/1` and owner-safe `close/1` root API
with an opaque document and a closed, redacted structured-error vocabulary.
README, module, milestone, export, typespec, and protocol checks establish that
no decode, projection, streaming, cursor, transfer, or raw native-handle
surface is exposed. Public corpora, ownership, lifetime, concurrency, and
native-baseline tests now exercise the packaged vertical slice.
Phase 6 Section 6.1 also makes the Hex archive buildable with explicit package
metadata, excludes generated Zigler intermediates, and inspects the unpacked
artifact for every required native source, header, provenance, and license.
Milestone 2 is defined by three accepted projection ADRs, three planned
subjects with explicit bootstrap exceptions, and a six-phase implementation
plan. Phase 1 now packages an undocumented internal projection validator and
extends the common error representation with reserved projection reasons and
an optional redacted path. Phase 2 packages ABI v2 descriptors, the opaque
C++ prefix-sharing plan, its Zig serializer/owner, independent conformance
harnesses, and the expanded private shared-ABI allowlist. Phase 3 now packages
the C++-only document/traversal coordination header, complete C guided-engine
corpus, and Zig typed-slot/cancellation cases alongside the still-private
execution engine. These remain internal build inputs: the root module still
exports only the Milestone 1 `open/1` and `close/1` operations, the NIF still
exports only `nif_init`, and no `select/2` or public compiled-plan surface is
present yet.

```spec-meta
id: simd_json.package
kind: package
status: active
summary: Active Milestone 1 library and native tooling with a fully specified, phased Milestone 2 projection plan.
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
  target: .spec/planning/milestone_02_projection_api/README.md
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
