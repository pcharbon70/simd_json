# Phase 3 — Package Metadata, Installation, and Public Documentation

Back to plan: [README](./README.md)

- [ ] 3 Phase - Make the archive and documentation complete enough for a Hex
  user to evaluate, install, compile, operate, and troubleshoot the library.

## 3.1 Section — Hex and ExDoc Metadata

- [ ] 3.1 Section - Complete consumer-visible package identity.
  - [ ] 3.1.1 Task - Normalize Mix project metadata.
    - [ ] 3.1.1.1 Subtask - Add explicit package name, maintainers, source URL, homepage, issue tracker, and documentation links.
    - [ ] 3.1.1.2 Subtask - Make license metadata match the Phase 1 license files.
    - [ ] 3.1.1.3 Subtask - Configure ExDoc source URL/ref and group milestone, operations, acceptance, changelog, and security pages.
  - [ ] 3.1.2 Task - Verify dependency metadata.
    - [ ] 3.1.2.1 Subtask - Ensure only production Hex dependencies appear in the published release.
    - [ ] 3.1.2.2 Subtask - Ensure Git-only SpecLed and Jason test dependencies are excluded from consumer resolution.
    - [ ] 3.1.2.3 Subtask - Review Elixir/OTP requirements for accuracy rather than broadening them without qualification.

## 3.2 Section — Installation and Native Build Guide

- [ ] 3.2 Section - Add copyable installation and prerequisite instructions.
  - [ ] 3.2.1 Task - Document Hex installation.
    - [ ] 3.2.1.1 Subtask - Add the exact dependency tuple for the release version.
    - [ ] 3.2.1.2 Subtask - Show dependency fetch, compilation, and one minimal decode/select/stream smoke test.
    - [ ] 3.2.1.3 Subtask - Distinguish supported, experimental, and unsupported environments.
  - [ ] 3.2.2 Task - Document source-native requirements.
    - [ ] 3.2.2.1 Subtask - List Zig/Zigler, C++ runtime, libc, build tools, CPU dispatch, and offline vendored-source behavior.
    - [ ] 3.2.2.2 Subtask - Explain expected compile time, cache location, common failures, and diagnostic commands.
    - [ ] 3.2.2.3 Subtask - State clearly that no precompiled NIF artifacts are shipped in the first release.

## 3.3 Section — Public Contract, Limits, and Release Notes

- [ ] 3.3 Section - Reconcile every public-facing claim with accepted behavior.
  - [ ] 3.3.1 Task - Correct and consolidate README guidance.
    - [ ] 3.3.1.1 Subtask - Mark Milestones 1–5 active on the qualified target.
    - [ ] 3.3.1.2 Subtask - Explain encoded-input retention versus avoided decoded-tree materialization.
    - [ ] 3.3.1.3 Subtask - Link operations, compatibility, saturation, telemetry, and acceptance records.
  - [ ] 3.3.2 Task - Add release communication files.
    - [ ] 3.3.2.1 Subtask - Add `CHANGELOG.md` with a complete `0.1.0` entry and explicit known limitations.
    - [ ] 3.3.2.2 Subtask - Add `SECURITY.md` with private reporting and supported-version policy chosen by the owner.
    - [ ] 3.3.2.3 Subtask - Add concise contributing/test instructions or link an existing authoritative guide.

## 3.4 Section — Archive Inventory and Documentation Proof

- [ ] 3.4 Section - Verify exactly what users receive.
  - [ ] 3.4.1 Task - Tighten the package allowlist.
    - [ ] 3.4.1.1 Subtask - Include root license, README, changelog, security guidance, runtime sources, native sources, provenance, and required docs.
    - [ ] 3.4.1.2 Subtask - Exclude tests, benchmarks, qualification outputs, caches, generated Zigler intermediates, editor files, and credentials.
    - [ ] 3.4.1.3 Subtask - Run Hex secret scanning and an additional deterministic secret-pattern inventory without suppressing genuine findings.
  - [ ] 3.4.2 Task - Execute package/doc gates.
    - [ ] 3.4.2.1 Subtask - Build and unpack the archive, assert required files, forbidden files, dependency metadata, size, and checksums.
    - [ ] 3.4.2.2 Subtask - Run ExDoc with warnings as errors and validate all local/source links for the release ref.
    - [ ] 3.4.2.3 Subtask - Render and inspect the README, API docs, changelog, license, and security pages as HexDocs will expose them.
