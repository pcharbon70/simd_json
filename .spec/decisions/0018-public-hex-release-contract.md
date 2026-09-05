---
id: simd_json.public_hex_release_contract
status: accepted
date: 2026-09-05
affects:
  - simd_json.package
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

## Consequences

Phase 1 will extend this decision with the owner-selected license, supported
target, credential boundary, and external-action rules. Later phases must keep
Mix, Hex, module, changelog, documentation, Git tag, and artifact identities
consistent. Any change after approval invalidates the candidate.
