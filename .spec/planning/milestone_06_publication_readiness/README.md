# Milestone 6 Publication Readiness and First Hex Release Plan

<!-- covers: simd_json.package.documentation_layout -->

This plan turns the accepted Milestone 1–5 implementation into an honest,
installable, reproducible first public Hex release. It fixes the cold-cache CI
failure, establishes licensing and package identity, documents source-build
requirements and the narrow supported target, qualifies the exact archive in a
fresh consumer project, and separates release preparation from the externally
visible publish action.

Planning this milestone does not authorize a Hex publication, tag, GitHub
release, credential change, or branch-protection change. Those actions remain
explicit gates in Phase 6.

## Source Authority

1. [Hex package publishing](https://hex.pm/docs/publish)
2. [Hex package immutability, revert, and retirement](https://hex.pm/docs/faq)
3. [Milestone 5 acceptance record](../../../docs/milestones/05-compatible-decode-api-acceptance.md)
4. [Package specification](../../specs/package.spec.md)
5. [Native build and ABI specification](../../specs/native_build_and_abi.spec.md)
6. Active Milestone 1–5 decisions, specifications, acceptance records, and
   qualification commands.

## Current Readiness Baseline

- The package builds and its offline consumer-native compilation gate passes.
- The local suite passes 15 doctests and 193 tests, including a 45.7 MB,
  one-million-row select/stream fixture.
- The latest completed `main` CI run fails because `mix format` cannot find the
  Zig formatter plugin after clean qualification steps.
- Project source has no root license file; vendored simdjson licenses do not
  establish the license for this wrapper.
- `README.md` has no Hex installation section and contains stale activation
  language for Milestones 4 and 5.
- There is no changelog, release checklist, first-release tag, or verified Hex
  publisher ownership.
- Only Ubuntu 24.04 x86-64 is qualified; other targets are experimental.

## Phase Order

1. [Phase 1 — Release Contract, Licensing, and Package Identity](./phase-01-release-contract-licensing-and-package-identity.md)
2. [Phase 2 — Cold-Cache CI Reliability and Merge Gates](./phase-02-cold-cache-ci-reliability-and-merge-gates.md)
3. [Phase 3 — Package Metadata, Installation, and Public Documentation](./phase-03-package-metadata-installation-and-public-documentation.md)
4. [Phase 4 — Release Tooling, Provenance, and Recovery](./phase-04-release-tooling-provenance-and-recovery.md)
5. [Phase 5 — Release-Candidate Qualification and Go/No-Go](./phase-05-release-candidate-qualification-and-go-no-go.md)
6. [Phase 6 — Version, Tag, Publish, and Post-Publish Verification](./phase-06-version-tag-publish-and-post-publish-verification.md)

## Contract Ownership by Phase

| Phase | Primary responsibility |
| --- | --- |
| 1 | Public/private destination, package name, semantic-version policy, project license, ownership, supported target, and release specification. |
| 2 | Deterministic clean-cache CI, formatter availability, merge protection, timeouts, and actionable evidence. |
| 3 | Hex metadata, installation and native prerequisites, supported behavior, memory semantics, changelog, security, and package inventory. |
| 4 | Read-only release checks, archive provenance, credential boundary, publication workflow, and recovery runbook. |
| 5 | Exact-archive consumer testing, full target qualification, repeatable CI, release-candidate evidence, and explicit approval. |
| 6 | Final version/release commit, tag, Hex publication, HexDocs and clean-consumer verification, monitoring, and acceptance. |

## Shared Conventions

- Checklist numbering uses phase `N`, section `N.M`, task `N.M.K`, and subtask
  `N.M.K.L`.
- Each section is one reviewable commit; one PR contains a complete phase.
- A checkbox closes only with implementation and executable evidence.
- No command may print, persist, upload, or archive a Hex API key.
- The package must build from a clean checkout without relying on restored CI
  cache state.
- “Supported” means the exact target passed package, ABI, sanitizer, scheduler,
  lifecycle, large-input, and consumer-install gates.
- Source JSON is loaded as one binary; select/stream avoid a full decoded BEAM
  tree but do not claim file/socket streaming or zero total-memory input.
- Publication requires explicit human approval after the Phase 5 go/no-go
  record. A green local run alone is insufficient.

## Milestone Exit Criteria

- The project license is explicitly chosen by the owner and shipped at the
  package root with matching Hex metadata.
- Pull-request and `main` CI pass twice from cold caches on the supported target.
- The Hex archive contains only reviewed files, no secrets or generated native
  artifacts, and compiles in a fresh consumer project without repository state.
- README, ExDoc, changelog, security guidance, support matrix, and limitations
  accurately describe the published version.
- Release identity binds version, commit, tree, tag, package checksum, toolchain,
  dependency lock, and immutable qualification evidence.
- An authorized publisher performs the explicit publish gate and immediately
  verifies Hex, HexDocs, and a fresh dependency installation.
- The recovery window, retirement procedure, and ownership contacts are known
  before publication.
