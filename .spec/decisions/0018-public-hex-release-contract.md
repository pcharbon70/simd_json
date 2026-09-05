---
id: simd_json.public_hex_release_contract
status: accepted
date: 2026-09-05
affects:
  - simd_json.package
  - simd_json.release
---

# Public Hex Release Contract

## Context

Milestones 1–5 establish a qualified library, but package publication creates
an immutable public distribution and a name, version, support, and ownership
promise. Repository success alone is not authorization to publish.

## Decision

The first release targets the public `hexpm` repository with OTP application
`:simd_json`, Hex package `simd_json`, and public modules under `SimdJson.*`.
The intended first version is `0.1.0`. While the major version is zero,
backward-incompatible public changes increment the minor version and compatible
fixes increment the patch version.

Release-candidate qualification uses the final numeric package version and
commit identity; it does not publish a separate prerelease package. The public
package name and version must be rechecked immediately before publication.
Only a clean, qualified, explicitly approved release commit may be tagged or
submitted to Hex.

Release qualification must bootstrap in one explicit Mix environment, verify
the pinned Zig executable before native compilation, rebuild Zigler before a
strict formatting gate, and record the active Hex archive and Rebar version.
Sanitizer, symbol, and offline builds use isolated temporary build and Zig
cache roots so their order cannot alter canonical inputs.

Superseded pull-request revisions may be cancelled, but `main` qualification
must never be cancelled by concurrency policy. CI keeps read-only repository
permissions, commit-pinned actions, bounded timeouts, partial failure evidence,
checksummed success evidence, and a summary naming status, gate, revision,
tree, and artifact path.

Release-preparation changes require separate cold-cache and restored-cache
GitHub checks at the pull-request head and resulting `main` commit. Both checks
must bind the same revision, tree, and qualification-input identity. Local
qualification is supporting evidence only. Branch-protection changes remain a
separate repository-owner mutation requiring explicit authorization naming
the branch and exact required checks.

The repository owner selected the MIT License for SimdJson wrapper code, with
copyright recorded as `Copyright (c) 2026 pcharbon70`. Vendored simdjson keeps
its separate upstream Apache-2.0-or-MIT license choice and attribution. Hex
package metadata names MIT for this wrapper and the archive ships all three
license texts plus a third-party notice.

The sole supported first-release target is Ubuntu 24.04 x86-64 with glibc
2.39, OTP 27.3, Elixir 1.18.4, Zig/Zigler 0.16.0, and vendored simdjson 4.6.9.
Every other target is experimental or unsupported until it passes the same
archive, ABI, sanitizer, lifecycle, scheduler, large-input, documentation, and
consumer-install matrix. Public operations receive a complete resident binary;
projection and streaming avoid a full decoded BEAM tree but do not provide
incremental file/socket input or zero total-memory handling.

## Consequences

Tag creation, Hex publication, revert, republish, retirement, and package-owner
changes are separate external mutations requiring explicit authorization for
an exact version and state. Publication credentials must never be committed,
logged, archived, echoed, or exposed to untrusted pull-request execution.

Later phases must keep
Mix, Hex, module, changelog, documentation, Git tag, and artifact identities
consistent. Any change after approval invalidates the candidate.
