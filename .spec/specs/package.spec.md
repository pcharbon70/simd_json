# SimdJson Package

Current package and documentation contract for the `SimdJson` library.

```spec-meta
id: simd_json.package
kind: package
status: active
summary: Elixir library scaffold, pinned native build tooling, local specification tooling, and implementation roadmap.
surface:
  - .tool-versions
  - mix.exs
  - mix.lock
  - lib/**/*.ex
  - native/manifest.exs
  - native/README.md
  - native/vendor/simdjson/**
  - test/**/*.exs
  - docs/milestones/*.md
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

- kind: source_file
  target: lib/simd_json.ex
  covers:
    - simd_json.package.mix_library

- kind: source_file
  target: docs/milestones/README.md
  covers:
    - simd_json.package.documentation_layout

- kind: source_file
  target: .spec/research/simdjson_beam_nif_architecture.md
  covers:
    - simd_json.package.documentation_layout

- kind: command
  target: mix test
  covers:
    - simd_json.package.mix_library
```
