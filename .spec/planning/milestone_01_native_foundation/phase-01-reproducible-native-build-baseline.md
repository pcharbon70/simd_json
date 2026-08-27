# Phase 1 — Reproducible Native Build Baseline

Back to plan: [README](./README.md)

- [ ] 1 Phase - Establish immutable native inputs and a clean-checkout build before parser behavior is implemented.

  This phase creates the supply-chain and build foundation consumed by every
  later phase. It selects compatible versions, vendors an exact official
  simdjson release with provenance and licensing, establishes the Zigler/Zig/C++
  build graph, declares the first qualified target, and makes unsupported
  targets fail explicitly. The phase ends with a linkable smoke NIF; it does not
  expose document parsing or claim ABI conformance yet.

  Contract focus:

  - `simd_json.native_build_and_abi.official_vendored_source`
  - `simd_json.native_build_and_abi.pinned_toolchain`
  - `simd_json.native_build_and_abi.clean_checkout_build`
  - `simd_json.native_build_and_abi.target_qualification`
  - `simd_json.native_build_and_abi.clean_supported_build`
  - `simd_json.native_build_and_abi.unsupported_target_rejection`
  - `simd_json.native_build_and_abi.dependency_upgrade_gate`

## 1.1 Section — Toolchain and Target Baseline

- [x] 1.1 Section - Select and record the complete ABI-relevant toolchain and the first qualification target.

  This section turns implicit workstation state into reviewed repository inputs.
  It defines which versions are immutable package inputs, which host tools have
  explicit supported ranges, and which operating-system and architecture pair
  is the primary Milestone 1 release target.

  - [x] 1.1.1 Task - Record the native toolchain manifest.

    The task defines one authoritative manifest for the Elixir/OTP, Zigler, Zig,
    C++ compiler and standard library, simdjson, build profile, and sanitizer
    versions used to qualify the NIF.

    - [x] 1.1.1.1 Subtask - Select a Zigler release or immutable commit whose supported Zig version and `:threaded` concurrency behavior can satisfy the accepted execution ADR.
    - [x] 1.1.1.2 Subtask - Pin Zigler in `mix.exs` and `mix.lock`, record its compatible Zig version, and ensure dependency resolution cannot follow a mutable branch.
    - [x] 1.1.1.3 Subtask - Record the supported Elixir and OTP range plus the exact CI versions used for qualification.
    - [x] 1.1.1.4 Subtask - Record the C++ compiler family, version or supported range, C++ language standard, standard-library implementation, target triple, and release/sanitizer profiles.
    - [x] 1.1.1.5 Subtask - Add a single human-readable native dependency manifest that links every pin to its verification source and upgrade procedure.

  - [x] 1.1.2 Task - Define the initial target and CPU-dispatch matrix.

    The task creates an explicit support table so compilation on an unknown host
    never implies that the resulting artifact is supported.

    - [x] 1.1.2.1 Subtask - Name one primary CI operating-system and architecture target that must close Milestone 1.
    - [x] 1.1.2.2 Subtask - Record the target's minimum OTP, Elixir, Zig, libc or platform runtime, C++ runtime, and expected simdjson runtime-dispatch implementations.
    - [x] 1.1.2.3 Subtask - Classify every other intended target as unsupported or experimental until equivalent conformance, sanitizer, and scheduler evidence exists.
    - [x] 1.1.2.4 Subtask - Define an explicit unsupported-target diagnostic containing the target triple and a link to the support matrix without silently changing compilers or parser implementations.

## 1.2 Section — Vendored simdjson Provenance

- [ ] 1.2 Section - Vendor one exact official simdjson release with independently verifiable provenance.

  This section makes the parser source part of the package rather than mutable
  host or network state. It retains upstream licensing and keeps any future
  local deviation separate and reviewable.

  - [ ] 1.2.1 Task - Select and import the official source release.

    The task chooses the smallest official simdjson release that meets the
    On-Demand, padding, runtime-dispatch, compiler, and supported-target needs of
    the accepted architecture.

    - [ ] 1.2.1.1 Subtask - Record the upstream release tag, immutable commit, canonical archive URL, and cryptographic archive digest before importing files.
    - [ ] 1.2.1.2 Subtask - Vendor only the upstream source and build metadata needed by this package while preserving the ability to compare the tree to the verified archive.
    - [ ] 1.2.1.3 Subtask - Store the upstream license and required notices in the distributed package and identify their inclusion in Hex package metadata.
    - [ ] 1.2.1.4 Subtask - Record the release's exact padding constant, supported C++ standard, supported compilers, and runtime CPU-dispatch contract for use in later phases.

  - [ ] 1.2.2 Task - Establish a no-hidden-patch policy.

    The task ensures local modifications cannot be mistaken for official
    upstream source and that a future dependency update regenerates all affected
    qualification evidence.

    - [ ] 1.2.2.1 Subtask - Keep each required local change as a separate patch with rationale, upstream reference, and digest rather than editing the vendor snapshot invisibly.
    - [ ] 1.2.2.2 Subtask - Add a verification command that reconstructs or checks the vendored tree against the upstream archive plus the declared patch series.
    - [ ] 1.2.2.3 Subtask - Document the dependency-upgrade gate requiring provenance, license, clean-build, C ABI, sanitizer, CPU-dispatch, and scheduler evidence to be regenerated.

## 1.3 Section — Offline Native Build Graph

- [ ] 1.3 Section - Compile and link a smoke native artifact without a system simdjson installation or build-time download.

  This section establishes the Elixir-to-Zigler-to-Zig-to-C++ build chain in its
  final direction while keeping the native behavior intentionally trivial until
  the C ABI phase defines its contract.

  - [ ] 1.3.1 Task - Add the Zigler and native compilation scaffold.

    The task wires the pinned build inputs into Mix and produces a loadable smoke
    NIF from the repository's own source tree.

    - [ ] 1.3.1.1 Subtask - Add the Zigler build configuration and native source layout used by all later C, C++, and Zig files.
    - [ ] 1.3.1.2 Subtask - Compile a minimal Zig entry module and C++ translation unit using the recorded target, language standard, include paths, and release profile.
    - [ ] 1.3.1.3 Subtask - Link only repository-vendored simdjson objects and fail the build if an ambient simdjson library would satisfy the link instead.
    - [ ] 1.3.1.4 Subtask - Ensure `mix compile` packages every required vendored source, header, license, and native build input for a clean consumer build.

  - [ ] 1.3.2 Task - Add deterministic build guards and diagnostics.

    The task makes unsupported or incomplete native environments fail early with
    actionable diagnostics rather than producing a subtly different artifact.

    - [ ] 1.3.2.1 Subtask - Validate the host target and ABI-relevant tool versions before native compilation begins.
    - [ ] 1.3.2.2 Subtask - Reject missing vendor files, checksum drift, undeclared patches, and incompatible tool versions before invoking the C++ compiler.
    - [ ] 1.3.2.3 Subtask - Add a test-only diagnostic that reports the target triple and simdjson runtime implementation without changing the public Elixir API.
    - [ ] 1.3.2.4 Subtask - Configure CI caches so they key on every ABI-relevant source digest and toolchain pin rather than reusing an artifact across incompatible inputs.

## 1.4 Section — Phase 1 Integration Tests

- [ ] 1.4 Section - Prove the native build is reproducible, self-contained, and target-gated.

  This section closes the build baseline with clean-environment evidence before
  any parser or resource code depends on it.

  - [ ] 1.4.1 Task - Run provenance and offline clean-build acceptance tests.

    The task verifies the `clean_supported_build` contract from a fresh checkout
    using only declared dependencies and the vendored official source.

    - [ ] 1.4.1.1 Subtask - Verify the simdjson archive digest, vendored-tree comparison, license files, notices, and patch manifest in CI.
    - [ ] 1.4.1.2 Subtask - After ordinary Mix dependencies are fetched, build from a clean workspace with network access disabled and no system simdjson installation.
    - [ ] 1.4.1.3 Subtask - Repeat the clean build and prove both runs consumed the same recorded source, target, compiler, Zig, Zigler, flags, and build profile.
    - [ ] 1.4.1.4 Subtask - Load the smoke NIF and assert its test-only target and runtime-dispatch diagnostics match the qualification matrix.

  - [ ] 1.4.2 Task - Run negative target and dependency-drift tests.

    The task proves unsupported environments and mutable dependency changes fail
    closed instead of silently changing the native implementation.

    - [ ] 1.4.2.1 Subtask - Exercise an unsupported-target test seam and assert the explicit target diagnostic is returned before compilation or load.
    - [ ] 1.4.2.2 Subtask - Corrupt a vendor checksum and alter an ABI-relevant pin in isolated fixtures, then assert both changes fail their guards.
    - [ ] 1.4.2.3 Subtask - Verify no native build script performs a network fetch, searches a system simdjson package, or follows a mutable Git reference.
    - [ ] 1.4.2.4 Subtask - Run the focused build tests, `mix test`, `mix spec.next`, and the reported `mix spec.check --base ...` command before marking Phase 1 complete.
