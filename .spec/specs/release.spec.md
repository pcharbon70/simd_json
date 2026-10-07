# First Public Hex Release

Release documentation, types, validation, and tests consistently publish
`:comma_delimited_json` as the comma-delimited top-level document format.

Release traceability recognizes executed `mix run` benchmark harnesses as
behavioral proof. The qualifying script must retain and validate its concrete
report artifacts, and a release regression contract binds that policy to the
million-row wide-projection qualification.

The release stream-performance follow-up changes the private NIF binding set,
so its source fingerprint, cumulative native matrix, precompiled artifact, and
consumer proof must be regenerated before publication. It does not authorize a
tag or release by itself.

Milestone 6 Phase 6 Section 6.4 adds the final non-publishing review. It
presents the exact proposed identity, defaults to no-go, and permits GO only
for an unconditional exact owner decision with green PR and main checks,
passed availability preflight, a loaded interactive credential, and unchanged
source. Any subsequent source change invalidates that decision.

Milestone 6 Phase 6 Section 6.3 assembles one bounded checksummed internal
review with source, package, native, toolchain, test, benchmark, legal,
security, consumer, recovery, and CI identities. Every gate has an evidence
path; credentials, source input, process identity, native addresses, and raw
logs are excluded, and pending authorization remains explicit.

Milestone 6 Phase 6 Section 6.2 installs only the built Hex tarball, a copied
production dependency, and the checksummed NIF into a fresh offline scratch
project. The Zig-free smoke covers every public operation, ownership,
capacity, telemetry, runtime dependency exclusions, and fail-closed artifact
and target errors without repository-relative consumer inputs.

Milestone 6 Phase 6 Section 6.1 adds the supported-target candidate gate. It
binds the complete cumulative safety program, two isolated native and archive
build roots, and the cold/restored pull-request and main checks to one commit,
tree, and qualification fingerprint without authorizing publication.

Milestone 6 Phase 5 follow-up qualification pins the release builder to generic
`x86_64-linux-gnu` so cold, restored, and publication runners attest the same
portable NIF bytes rather than host-specific CPU output.
The Zig-free consumer harness also selects the setup-beam or asdf Mix archive
home before isolating PATH, ensuring it can use installed Hex without exposing
Zig or changing the published package.
The restored-cache release qualification receives a 60-minute step budget and
the matrix job a 75-minute budget after the exact portable two-build proof
reached the former 45-minute step ceiling; both limits remain bounded above
the observed complete cold-cache duration.

Current-truth contract for preparing and publishing the first public release.
Milestone 6 Phase 1 freezes identity, licensing, and support; Phases 2–8 own CI
repair, public package documentation, release tooling, exact-candidate
qualification, native file-backed input remediation, explicit authorization,
publication, and external verification. Phase 7 invalidates every preceding
candidate until its corrected native surface is fully requalified.
Phase 3 Section 3.1 adds explicit Hex identity, maintainer and public links,
tag-bound ExDoc source metadata, documentation groups, and executable proof
that telemetry is the required runtime dependency while Zigler is an optional
source-build dependency under the qualified Elixir requirement.
Section 3.2 adds a copyable dependency and compilation sequence, executable
decode/select/stream smoke workflows, the exact supported versus experimental
boundary, precompiled and optional source-native behavior, cache and download
expectations, and diagnostic recovery commands. Phase 5 supersedes its earlier
source-only delivery decision.
Section 3.3 reconciles README memory, compatibility, operations, saturation,
telemetry, and acceptance links; publishes complete 1.0.0 release notes and
known limits; selects private email reporting and newest-patch-only security
support; and documents the contributor bootstrap, test, SpecLed, and native
qualification workflow.
Section 3.4 replaces broad package directories with an explicit runtime,
native-source, provenance, license, and documentation allowlist. One executable
gate runs Hex's no-publish checks, deterministic secret-pattern inventory,
archive metadata/size/checksums, strict HTML generation, rendered-page markers,
local links, and v1.0.0 API source links while rejecting development and
generated files.
Phase 4 Section 4.1 adds one credential-free preflight command. It requires a
clean main branch whose HEAD matches both local and live remote origin/main,
exact Mix/changelog/ExDoc/tag identity, and absent local, remote, and public Hex
versions. It composes formatter, strict docs, package inventory, native
qualification freshness, and structural SpecLed gates into a bounded,
checksummed report without creating Git, GitHub, or Hex state.
Section 4.2 builds the source archive twice in isolated directories and
requires both normalized contents and exact archive bytes to match. It retains
the exact candidate with commit, tree, lock, toolchain, target, native
fingerprint, source-manifest, dependency/license-inventory, and archive
checksums in the fixed-retention CI evidence artifact.
Section 4.3 records `pcharbon70` as the read-only verified Hex publisher and
pre-publication recovery owner, selects an interactive reviewed first release,
and prohibits CI publication. Its identity check refuses loaded publication
credentials; any later CI publisher requires a separate owner decision,
manual protected dispatch, an exact tag, and a short-lived package-scoped key.
Section 4.4 records current initial-package and later-version recovery windows,
assigns revert, patch, retirement, credential, advisory, and GitHub correction
decisions, and adds a non-mutating rehearsal. Synthetic evidence proves
missing docs, broken native compilation, checksum corruption, and secret
matches all fail closed before any external release action.
Phase 5 supersedes the earlier source-only installation decision for supported
consumers. It keeps Zigler as an optional audit/source-build dependency, binds
one release asset to version, target, and SHA-256, and loads the existing NIF
entry table without Zig or generated native files in the Hex archive. Missing,
unsupported, corrupt, or replaced artifacts fail before native loading.
The release-safe artifact is reproduced from two isolated builds, its runtime
dependencies and sole exported symbol are checked, and a packaged consumer
executes without Zig. GitHub must serve those exact approved bytes before Hex
publication because consumer compilation depends on the release asset.
Phase 2 Section 2.2 now rebuilds the pinned Zigler formatter in an explicit
test environment after verifying Zig 0.16.0 and recording Hex/Rebar. It also
closes the reproduced pool-retirement, stale-baseline, and collected-request
demonitor failures. Terminal workers use only job-retained native controls and
leave collected resource monitor removal to ERTS. Workflow safety in Section
2.3 now cancels only superseded pull requests, bounds the job, retains partial
or checksummed evidence, and reports the failed gate with revision and tree.
Section 2.4 makes cold and restored qualification separate required checks,
records cache state and qualification identity, and prohibits merge while
either check is not green. Branch-protection settings remain an explicitly
authorized repository-owner action.

```spec-meta
id: simd_json.release
kind: feature
status: planned
summary: Milestone 6 will publish the MIT-licensed simd_json 1.0.0 source package to public Hex after cold-cache CI, exact-archive qualification, and explicit owner approval.
surface:
  - mix.exs
  - LICENSE
  - THIRD_PARTY_NOTICES.md
  - README.md
  - CHANGELOG.md
  - SECURITY.md
  - CONTRIBUTING.md
  - docs/guides/*.md
  - docs/benchmarks/**/*.md
  - docs/releases/*.md
  - .github/workflows/*.yml
  - scripts/ci/validate_exdoc_links.exs
  - scripts/ci/generate_dependency_inventory.exs
  - scripts/ci/verify_package_documentation.sh
  - scripts/ci/qualify_release_candidate.sh
  - scripts/release/assemble_candidate_evidence.sh
  - scripts/release/review_go_no_go.sh
  - scripts/release/preflight.sh
  - scripts/release/verify_publisher.sh
  - scripts/release/verify_candidate_evidence.sh
  - scripts/release/rehearse_recovery.sh
  - release/publisher-policy.env
  - test/release/*.exs
decisions:
  - simd_json.public_hex_release_contract
  - simd_json.native_file_backed_input_and_batched_streaming
bootstrap:
  reason: Phase 1 freezes release identity, licensing, support, and authorization boundaries; CI repair, public documentation, tooling, precompiled delivery, candidate qualification, publication, and post-publish verification remain in Phases 2 through 7.
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
    - simd_json.release.read_only_preflight
    - simd_json.release.publisher_boundary
    - simd_json.release.recovery_readiness
    - simd_json.release.precompiled_delivery
```

## Requirements

```spec-requirements
- id: simd_json.release.public_identity
  statement: The first release shall consistently identify public Hex package simd_json, OTP application :simd_json, SimdJson modules, semantic version 1.0.0, and one exact Git commit and tag.
  priority: must
  stability: stable

- id: simd_json.release.project_license
  statement: Wrapper code shall ship under the owner-selected MIT License while vendored simdjson retains its separate complete Apache-2.0-or-MIT notices and provenance.
  priority: must
  stability: stable

- id: simd_json.release.qualified_support
  statement: Public documentation shall claim support only for the exact qualified Ubuntu 24.04 x86-64 toolchain, present native file-backed processing as the principal large-document capability, and distinguish mapped source bytes, simdjson parser working memory, bounded result batches, and eager decoded-tree allocation.
  priority: must
  stability: evolving

- id: simd_json.release.file_input_gate
  statement: No release commit, tag, GitHub release, or Hex publication shall proceed until open_file, select_file, and batched stream_file pass the complete supported-target, memory-scaling, archive, precompiled-NIF, and Zig-free consumer matrix at the proposed commit.
  priority: must
  stability: evolving

- id: simd_json.release.green_ci
  statement: The exact release commit shall pass required pull-request and main CI from cold and restored caches with no pending or red check.
  priority: must
  stability: evolving

- id: simd_json.release.archive_integrity
  statement: The reviewed Hex archive shall contain every required runtime, native, documentation, license, and provenance file and no secret, generated binary, cache, or development-only dependency.
  priority: must
  stability: evolving

- id: simd_json.release.consumer_documentation
  statement: README and HexDocs shall provide concise, feature-oriented user guidance for precompiled installation, optional source-build prerequisites, supported environments, public API behavior, limits, security contact, changelog, and troubleshooting, and shall exclude internal roadmap, phase, milestone, acceptance, qualification-history, and release-process language from the published documentation and Hex archive.
  priority: must
  stability: evolving

- id: simd_json.release.provenance
  statement: Release evidence shall bind version, commit, tree, tag, package checksum, dependency lock, toolchain, native fingerprint, target, tests, source manifest, transitive dependency licenses, reproducibility proof, and qualification artifacts.
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

- id: simd_json.release.read_only_preflight
  statement: One non-publishing command shall require clean synchronized main, consistent version and tag identity, absent local, remote, and Hex release identity, and current formatting, documentation, package, qualification, and SpecLed proof while emitting only bounded non-secret evidence.
  priority: must
  stability: evolving

- id: simd_json.release.publisher_boundary
  statement: The intended Hex publisher and recovery owner shall be recorded and verified without loading a publication credential; the first release shall use an interactive reviewed session while CI publication remains disabled unless separately owner-approved with a protected manual workflow and short-lived package-scoped key.
  priority: must
  stability: stable

- id: simd_json.release.recovery_readiness
  statement: A dated runbook shall require current Hex-window reverification, assign authority for revert, patch, retirement, credential, advisory, and GitHub correction choices, and rehearse all evidence-failure paths without mutating a real release.
  priority: must
  stability: evolving

- id: simd_json.release.precompiled_delivery
  statement: Supported package consumers shall obtain one immutable target-specific production NIF whose SHA-256 digest is committed and verified before loading, without requiring Zig or Zigler, while maintainers retain an explicit qualified source-build path.
  priority: must
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: simd_json.release.preflight_is_read_only
  covers:
    - simd_json.release.read_only_preflight
  given:
    - A proposed semantic version and matching tag
    - No publication credential in the process environment
  when:
    - Release preflight runs from a clean main checkout
  then:
    - HEAD matches local and live remote origin/main
    - Local, remote, and public Hex release identities are absent
    - Existing formatter, documentation, package, freshness, and SpecLed gates pass
    - A bounded checksummed report is written without mutating Git, GitHub, or Hex

- id: simd_json.release.archive_is_reproducible
  covers:
    - simd_json.release.archive_integrity
    - simd_json.release.provenance
  given:
    - One clean committed release-candidate source tree
  when:
    - The package gate builds the Hex archive twice in isolated directories
  then:
    - Both normalized source manifests and exact archive SHA-256 digests match
    - Provenance binds the candidate to source, toolchain, native, dependency, and target identities
    - Checksummed evidence retains the exact archive in the commit-qualified CI artifact for 30 days

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
    - simd_json.release.file_input_gate
    - simd_json.release.explicit_authorization
  given:
    - A completely green candidate with verified package ownership and credentials
  when:
    - The owner reviews the exact version, commit, tag, destination, checksum, and command
  then:
    - Publication proceeds only after explicit approval
    - Any source or identity change invalidates approval and returns to qualification
    - Candidate evidence created before the accepted file-input correction is rejected

- id: simd_json.release.publisher_identity_is_read_only
  covers:
    - simd_json.release.publisher_boundary
    - simd_json.release.explicit_authorization
  given:
    - The tracked publisher policy and no publication key in the process
  when:
    - Publisher identity verification runs
  then:
    - The authenticated Hex username matches the intended publisher
    - A recovery owner and contact are present
    - Only bounded non-secret evidence is written and no Hex state changes

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

- id: simd_json.release.recovery_rehearsal_is_non_mutating
  covers:
    - simd_json.release.recovery_readiness
    - simd_json.release.explicit_authorization
  given:
    - Synthetic candidate evidence and the tracked recovery runbook
  when:
    - The local recovery rehearsal runs
  then:
    - Missing docs, failed native compilation, checksum mismatch, and a secret marker are detected
    - Owner contact, key revocation, private advisory, and GitHub correction paths are present
    - No Hex or GitHub release state is created, changed, or removed

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
    - The recorded sanitizer, lifecycle, and collected-request failure cases
  when:
    - Isolated sanitizer, repeated native, and full-suite regression runs execute
  then:
    - Every run exits normally without a VM abort
    - Every run starts and finishes with quiescent native lifecycle gauges

- id: simd_json.release.precompiled_loader_is_fail_closed
  covers:
    - simd_json.release.precompiled_delivery
  given:
    - A package version, normalized supported target, immutable release asset, and committed SHA-256 digest
  when:
    - A consumer compiles the dependency without Zig or Zigler
  then:
    - The exact artifact is verified before installation and NIF loading
    - Decode, select, stream, lifecycle, telemetry, and diagnostics retain their source-built behavior
    - Missing targets, downloads, digests, or artifacts fail without loading native code
    - An explicit maintainer override may rebuild from the qualified source inputs
```

## Verification

```spec-verification
- kind: command
  target: MIX_ENV=test mix test test/release/release_tooling_contract_test.exs
  execute: true
  covers:
    - simd_json.release.read_only_preflight
    - simd_json.release.archive_integrity
    - simd_json.release.provenance
    - simd_json.release.publisher_boundary
    - simd_json.release.recovery_readiness

- kind: command
  target: MIX_ENV=test mix test test/release/release_contract_test.exs
  execute: true
  covers:
    - simd_json.release.public_identity
    - simd_json.release.project_license
    - simd_json.release.qualified_support
    - simd_json.release.publication_gate

- kind: command
  target: MIX_ENV=test mix test test/release/package_documentation_contract_test.exs
  execute: true
  covers:
    - simd_json.release.public_identity
    - simd_json.release.project_license
    - simd_json.release.archive_integrity
    - simd_json.release.consumer_documentation

- kind: command
  target: bash scripts/ci/verify_package_documentation.sh
  execute: true
  covers:
    - simd_json.release.archive_integrity
    - simd_json.release.consumer_documentation
    - simd_json.release.provenance

- kind: command
  target: bash scripts/release/rehearse_recovery.sh
  execute: true
  covers:
    - simd_json.release.recovery_readiness
    - simd_json.release.explicit_authorization

- kind: command
  target: MIX_ENV=test mix test test/release/ci_reliability_contract_test.exs test/native/pool_delivery_test.exs test/native/pool_worker_lifecycle_test.exs test/native/decode_pool_lifecycle_test.exs
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
    - simd_json.release.file_input_gate

- kind: command
  target: bash scripts/ci/verify_precompiled_consumer.sh
  execute: false
  covers:
    - simd_json.release.precompiled_delivery
```
