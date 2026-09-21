# Phase 5 — Precompiled NIF Delivery

Back to plan: [README](./README.md)

- [ ] 5 Phase - Deliver the qualified production NIF without requiring Zig on
  supported consumer machines while retaining an explicit source-build path.

## 5.1 Section — Artifact and Loader Contract

- [x] 5.1 Section - Define a fail-closed precompiled artifact boundary.
  - [x] 5.1.1 Task - Select the supported artifact deterministically.
    - [x] 5.1.1.1 Subtask - Bind the package version and normalized target triple to one immutable asset name and lowercase SHA-256 digest.
    - [x] 5.1.1.2 Subtask - Reject missing targets, missing checksums, malformed manifests, and checksum mismatches before loading native code.
    - [x] 5.1.1.3 Subtask - Keep repository tests and an explicit environment-controlled audit path source-built.
  - [x] 5.1.2 Task - Preserve the accepted NIF boundary.
    - [x] 5.1.2.1 Subtask - Bind the existing direct, marshalled, and threaded NIF entry table so resources, callbacks, and the private NIF surface remain unchanged without compiling Zigler on consumer machines.
    - [x] 5.1.2.2 Subtask - Prove source and precompiled modes expose the same public Elixir API and runtime diagnostics.

## 5.2 Section — Reproducible Artifact and Provenance

- [x] 5.2 Section - Build and attest the exact release artifact.
  - [x] 5.2.1 Task - Add a bounded supported-target artifact builder.
    - [x] 5.2.1.1 Subtask - Produce the release-safe NIF twice from isolated roots and require byte-identical SHA-256 digests.
    - [x] 5.2.1.2 Subtask - Verify target, dynamic dependencies, exported symbols, NIF entry compatibility, and native diagnostics.
    - [x] 5.2.1.3 Subtask - Emit a checksummed manifest binding asset, source commit/tree, native fingerprint, toolchain, and target.
  - [x] 5.2.2 Task - Integrate the artifact with release evidence.
    - [x] 5.2.2.1 Subtask - Require the committed checksum manifest to match the reproduced candidate artifact.
    - [x] 5.2.2.2 Subtask - Preserve source inputs in Hex while excluding generated native binaries from the Hex archive.

## 5.3 Section — Zig-Free Consumer and CI Gates

- [ ] 5.3 Section - Prove supported consumers do not need Zig.
  - [ ] 5.3.1 Task - Exercise a clean packaged consumer.
    - [ ] 5.3.1.1 Subtask - Compile the unpacked Hex dependency with Zig unavailable and only the checksummed candidate artifact supplied.
    - [ ] 5.3.1.2 Subtask - Run decode, select, stream, lifecycle, telemetry, and runtime-diagnostic smoke checks.
    - [ ] 5.3.1.3 Subtask - Corrupt the artifact and checksum independently and prove both paths fail before NIF loading.
  - [ ] 5.3.2 Task - Add non-publishing artifact CI.
    - [ ] 5.3.2.1 Subtask - Build and retain the candidate NIF as an Actions artifact without creating a tag, GitHub release, or Hex publication.
    - [ ] 5.3.2.2 Subtask - Add the Zig-free consumer gate to cumulative cold and restored qualification.

## 5.4 Section — Publication Flow and Documentation Reconciliation

- [ ] 5.4 Section - Make artifact ordering and user guidance accurate.
  - [ ] 5.4.1 Task - Document supported installation and fallback behavior.
    - [ ] 5.4.1.1 Subtask - Make ordinary supported-target installation require no Zig compiler while documenting network, cache, checksum, and source-build behavior.
    - [ ] 5.4.1.2 Subtask - Keep unsupported targets experimental or rejected rather than silently compiling unqualified native code.
  - [ ] 5.4.2 Task - Reconcile release ordering and recovery.
    - [ ] 5.4.2.1 Subtask - Require the checksummed GitHub release asset to exist before Hex publication because consumer compilation downloads that immutable asset.
    - [ ] 5.4.2.2 Subtask - Verify asset deletion, replacement, checksum mismatch, and download failure recovery paths without external mutation.
    - [ ] 5.4.2.3 Subtask - Renumber candidate qualification and publication as Phases 6 and 7 and reconcile specifications, fingerprints, package inventory, and phase links.
