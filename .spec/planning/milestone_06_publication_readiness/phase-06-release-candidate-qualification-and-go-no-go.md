# Phase 6 — Release-Candidate Qualification and Go/No-Go

Back to plan: [README](./README.md)

- [ ] 6 Phase - Qualify the exact archive and obtain an explicit release
  decision before creating externally visible release state.

## 6.1 Section — Supported-Target Clean Qualification

- [ ] 6.1 Section - Rerun the complete safety program at release identity.
  - [ ] 6.1.1 Task - Execute cumulative qualification.
    - [ ] 6.1.1.1 Subtask - Run native ABI, ordinary, ASan/UBSan, race, symbols, lifecycle, cancellation, saturation, and shutdown gates.
    - [ ] 6.1.1.2 Subtask - Run projection, stream, decode, Jason differential, scheduler, memory, and million-row qualification.
    - [ ] 6.1.1.3 Subtask - Run strict formatting, docs, full tests, SpecLed validation/impact/traceability, and fingerprint freshness.
  - [ ] 6.1.2 Task - Prove clean-cache repeatability.
    - [ ] 6.1.2.1 Subtask - Pass two Ubuntu 24.04 x86-64 runs from independent clean build roots.
    - [ ] 6.1.2.2 Subtask - Pass the same commit on GitHub pull-request and `main` workflows with matching source tree and fingerprint.

## 6.2 Section — Fresh Consumer Archive Tests

- [ ] 6.2 Section - Test what a user installs rather than the repository checkout.
  - [ ] 6.2.1 Task - Create isolated consumer projects.
    - [ ] 6.2.1.1 Subtask - Install only the locally built Hex tarball plus production dependencies in a fresh Mix project.
    - [ ] 6.2.1.2 Subtask - Compile with no network access after dependency/cache preparation and no repository-relative files.
    - [ ] 6.2.1.3 Subtask - Run decode, projection, streaming, ownership, saturation, and telemetry smoke tests against the installed archive.
  - [ ] 6.2.2 Task - Exercise installation failures.
    - [ ] 6.2.2.1 Subtask - Verify unsupported target/toolchain failures are early, bounded, and actionable.
    - [ ] 6.2.2.2 Subtask - Verify missing compiler/Zig prerequisites do not leave partial generated artifacts or misleading success.
    - [ ] 6.2.2.3 Subtask - Confirm runtime applications exclude Jason, SpecLed, ExDoc, and other development-only dependencies.

## 6.3 Section — Release-Candidate Evidence Bundle

- [ ] 6.3 Section - Produce one reviewable, checksummed candidate record.
  - [ ] 6.3.1 Task - Aggregate evidence.
    - [ ] 6.3.1.1 Subtask - Include CI URLs, source identity, package checksum/inventory, docs result, test counts, target/toolchain, and benchmark acceptance.
    - [ ] 6.3.1.2 Subtask - Include licensing, ownership, name/version availability, security scan, consumer install, and recovery readiness.
    - [ ] 6.3.1.3 Subtask - Exclude credentials, source inputs, PIDs, native addresses, and unbounded logs from the summary.
  - [ ] 6.3.2 Task - Publish an internal candidate summary.
    - [ ] 6.3.2.1 Subtask - Mark each gate pass/fail with an evidence path rather than prose-only claims.
    - [ ] 6.3.2.2 Subtask - Record remaining experimental platforms and deferred features as non-blocking only when public docs agree.

## 6.4 Section — Explicit Go/No-Go Review

- [ ] 6.4 Section - Stop before publication and request owner authorization.
  - [ ] 6.4.1 Task - Complete review signoffs.
    - [ ] 6.4.1.1 Subtask - Confirm license/copyright authority and third-party notices.
    - [ ] 6.4.1.2 Subtask - Confirm package/version/name, publisher/recovery owners, support promise, changelog, and recovery runbook.
    - [ ] 6.4.1.3 Subtask - Confirm exact release commit has green required GitHub checks with no pending run.
  - [ ] 6.4.2 Task - Obtain a concrete decision.
    - [ ] 6.4.2.1 Subtask - Present the exact version, commit, tag, package checksum, destination, and publish command for approval.
    - [ ] 6.4.2.2 Subtask - Treat silence, conditional approval, red/pending CI, changed source, or missing credentials as no-go.
    - [ ] 6.4.2.3 Subtask - Any post-approval source change invalidates approval and returns to qualification.
