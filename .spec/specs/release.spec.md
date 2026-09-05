# First Public Hex Release

Current-truth contract for preparing and publishing the first public release.
Milestone 6 Phase 1 freezes identity, licensing, and support; Phases 2–6 own CI
repair, public package documentation, release tooling, exact-candidate
qualification, explicit authorization, publication, and external verification.
Phase 2 Section 2.2 now rebuilds the pinned Zigler formatter in an explicit
test environment after verifying Zig 0.16.0 and recording Hex/Rebar. It also
closes the reproduced pool-retirement and stale-baseline failures; workflow
safety in Section 2.3 now cancels only superseded pull requests, bounds the
job, retains partial or checksummed evidence, and reports the failed gate with
revision and tree. Cold/restored GitHub proof remains in Section 2.4.

```spec-meta
id: simd_json.release
kind: feature
status: planned
summary: Milestone 6 will publish the MIT-licensed simd_json 0.1.0 source package to public Hex after cold-cache CI, exact-archive qualification, and explicit owner approval.
surface:
  - mix.exs
  - LICENSE
  - THIRD_PARTY_NOTICES.md
  - README.md
  - docs/releases/*.md
  - .github/workflows/*.yml
  - test/release/*.exs
decisions:
  - simd_json.public_hex_release_contract
bootstrap:
  reason: Phase 1 freezes release identity, licensing, support, and authorization boundaries; CI repair, public documentation, tooling, candidate qualification, publication, and post-publish verification remain in Phases 2 through 6.
  requirements:
    - simd_json.release.public_identity
    - simd_json.release.project_license
    - simd_json.release.qualified_support
    - simd_json.release.green_ci
    - simd_json.release.archive_integrity
    - simd_json.release.consumer_documentation
    - simd_json.release.provenance
    - simd_json.release.explicit_authorization
    - simd_json.release.post_publish_verification
```

## Requirements

```spec-requirements
- id: simd_json.release.public_identity
  statement: The first release shall consistently identify public Hex package simd_json, OTP application :simd_json, SimdJson modules, semantic version 0.1.0, and one exact Git commit and tag.
  priority: must
  stability: stable

- id: simd_json.release.project_license
  statement: Wrapper code shall ship under the owner-selected MIT License while vendored simdjson retains its separate complete Apache-2.0-or-MIT notices and provenance.
  priority: must
  stability: stable

- id: simd_json.release.qualified_support
  statement: Public documentation shall claim support only for the exact qualified Ubuntu 24.04 x86-64 toolchain and shall distinguish complete input-binary residency from avoided decoded-tree allocation.
  priority: must
  stability: stable

- id: simd_json.release.green_ci
  statement: The exact release commit shall pass required pull-request and main CI from cold and restored caches with no pending or red check.
  priority: must
  stability: evolving

- id: simd_json.release.archive_integrity
  statement: The reviewed Hex archive shall contain every required runtime, native, documentation, license, and provenance file and no secret, generated binary, cache, or development-only dependency.
  priority: must
  stability: evolving

- id: simd_json.release.consumer_documentation
  statement: README and HexDocs shall provide accurate installation, source-build prerequisites, supported environments, public API behavior, limits, security contact, changelog, and troubleshooting guidance.
  priority: must
  stability: evolving

- id: simd_json.release.provenance
  statement: Release evidence shall bind version, commit, tree, tag, package checksum, dependency lock, toolchain, native fingerprint, target, tests, and qualification artifacts.
  priority: must
  stability: evolving

- id: simd_json.release.explicit_authorization
  statement: Tag, publish, revert, republish, retire, and package-owner mutations shall require an explicit decision naming the exact version and target state, and credentials shall never enter source or evidence.
  priority: must
  stability: stable

- id: simd_json.release.post_publish_verification
  statement: Acceptance shall require verification of public Hex metadata, HexDocs, tarball checksum, ownership, and a clean supported-target consumer installation during the current recovery window.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.release.candidate_preflight
  covers:
    - simd_json.release.green_ci
    - simd_json.release.archive_integrity
    - simd_json.release.consumer_documentation
    - simd_json.release.provenance
  given:
    - A clean synchronized main revision with an approved semantic version
  when:
    - Release-candidate qualification runs from clean and restored caches
  then:
    - The exact archive compiles in a fresh consumer on the qualified target
    - Evidence binds every public, package, native, documentation, and source identity

- id: simd_json.release.publication_gate
  covers:
    - simd_json.release.public_identity
    - simd_json.release.project_license
    - simd_json.release.qualified_support
    - simd_json.release.explicit_authorization
  given:
    - A completely green candidate with verified package ownership and credentials
  when:
    - The owner reviews the exact version, commit, tag, destination, checksum, and command
  then:
    - Publication proceeds only after explicit approval
    - Any source or identity change invalidates approval and returns to qualification

- id: simd_json.release.public_verification
  covers:
    - simd_json.release.post_publish_verification
  given:
    - Hex reports successful first publication
  when:
    - Maintainers inspect public metadata, docs, archive, and a fresh dependency install
  then:
    - Matching public evidence activates the release subject
    - A material defect follows the pre-approved patch, revert, or retirement runbook

- id: simd_json.release.ci_cache_equivalence
  covers:
    - simd_json.release.green_ci
  given:
    - One exact revision on the qualified GitHub runner
  when:
    - The required workflow runs once with empty dependency and native caches
    - The same workflow runs again with restored caches
  then:
    - Both runs bootstrap the formatter and native toolchain in the same explicit Mix environment
    - Both runs pass and report the same qualification input identity

- id: simd_json.release.ci_native_reliability
  covers:
    - simd_json.release.green_ci
  given:
    - The recorded sanitizer and lifecycle failure seeds
  when:
    - Isolated sanitizer, repeated native, and full-suite regression runs execute
  then:
    - Every run exits normally without a VM abort
    - Every run starts and finishes with quiescent native lifecycle gauges
```

## Verification

```spec-verification
- kind: command
  target: MIX_ENV=test mix test test/release/release_contract_test.exs
  execute: true
  covers:
    - simd_json.release.public_identity
    - simd_json.release.project_license
    - simd_json.release.qualified_support
    - simd_json.release.publication_gate

- kind: command
  target: MIX_ENV=test mix test test/release/ci_reliability_contract_test.exs test/native/pool_worker_lifecycle_test.exs test/native/decode_pool_lifecycle_test.exs
  execute: true
  covers:
    - simd_json.release.green_ci
    - simd_json.release.ci_cache_equivalence
    - simd_json.release.ci_native_reliability

- kind: command
  target: SIMD_JSON_NIF_SANITIZER_SEED=935088 bash scripts/native/run_nif_sanitizer_tests.sh
  execute: true
  covers:
    - simd_json.release.green_ci
    - simd_json.release.ci_native_reliability

- kind: command
  target: bash scripts/ci/qualify_release_candidate.sh
  execute: false
  covers:
    - simd_json.release.green_ci
    - simd_json.release.archive_integrity
    - simd_json.release.consumer_documentation
    - simd_json.release.provenance
    - simd_json.release.explicit_authorization
    - simd_json.release.post_publish_verification
    - simd_json.release.candidate_preflight
    - simd_json.release.public_verification
```
