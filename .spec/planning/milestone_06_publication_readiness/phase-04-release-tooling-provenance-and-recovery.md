# Phase 4 — Release Tooling, Provenance, and Recovery

Back to plan: [README](./README.md)

- [ ] 4 Phase - Build a repeatable release procedure with a narrow credential
  boundary, immutable provenance, and a rehearsed recovery path.

## 4.1 Section — Read-Only Release Preflight

- [ ] 4.1 Section - Add one non-publishing command that proves release inputs.
  - [ ] 4.1.1 Task - Validate repository identity.
    - [ ] 4.1.1.1 Subtask - Require clean `main`, exact synchronization with `origin/main`, and no untracked package files.
    - [ ] 4.1.1.2 Subtask - Require semantic version agreement across Mix, changelog, docs source ref, and proposed tag.
    - [ ] 4.1.1.3 Subtask - Reject an existing local/remote tag or an already-published Hex version.
  - [ ] 4.1.2 Task - Compose existing gates.
    - [ ] 4.1.2.1 Subtask - Run formatter bootstrap/check, strict docs, package inventory, qualification freshness, and SpecLed validation.
    - [ ] 4.1.2.2 Subtask - Emit a bounded machine-readable preflight report without modifying Git, Hex, or GitHub state.

## 4.2 Section — Release Archive and Provenance

- [ ] 4.2 Section - Bind the exact candidate archive to reviewed source.
  - [ ] 4.2.1 Task - Record immutable identity.
    - [ ] 4.2.1.1 Subtask - Record version, commit, tree, dependency lock, toolchain, target, native fingerprint, and package checksum.
    - [ ] 4.2.1.2 Subtask - Generate a dependency/license inventory and source-file manifest.
    - [ ] 4.2.1.3 Subtask - Store checksummed candidate evidence as a CI artifact with fixed retention.
  - [ ] 4.2.2 Task - Prove reproducibility.
    - [ ] 4.2.2.1 Subtask - Build the package twice in isolated directories and compare normalized contents.
    - [ ] 4.2.2.2 Subtask - Explain or eliminate any nondeterministic archive fields before approval.

## 4.3 Section — Publisher Authentication and Workflow Boundary

- [ ] 4.3 Section - Define publishing without weakening repository security.
  - [ ] 4.3.1 Task - Establish publisher ownership.
    - [ ] 4.3.1.1 Subtask - Verify the intended confirmed Hex account or organization and at least one recovery owner.
    - [ ] 4.3.1.2 Subtask - Use a short-lived, least-privilege publication key only if CI publication is owner-approved.
    - [ ] 4.3.1.3 Subtask - Keep credentials out of commands, logs, artifacts, shell history, repository files, and AI-visible output.
  - [ ] 4.3.2 Task - Choose the first-release execution model.
    - [ ] 4.3.2.1 Subtask - Prefer an interactive reviewed first publication unless the owner explicitly approves a protected CI release environment.
    - [ ] 4.3.2.2 Subtask - If automated, require manual dispatch, exact tag input, protected environment approval, and no pull-request secret access.
    - [ ] 4.3.2.3 Subtask - Separate preflight from the command that mutates Hex state.

## 4.4 Section — Recovery and Retirement Runbook

- [ ] 4.4 Section - Rehearse what happens when publication is wrong.
  - [ ] 4.4.1 Task - Document response windows and choices.
    - [ ] 4.4.1.1 Subtask - Reverify Hex's current revert windows immediately before release.
    - [ ] 4.4.1.2 Subtask - Define when to revert, publish a patch, or retire a release and who decides.
    - [ ] 4.4.1.3 Subtask - Record commands as examples that still require explicit confirmation and exact version input.
  - [ ] 4.4.2 Task - Rehearse without mutating Hex.
    - [ ] 4.4.2.1 Subtask - Simulate missing docs, broken native compile, checksum mismatch, and leaked-secret responses.
    - [ ] 4.4.2.2 Subtask - Verify owner contact, credential revocation, advisory, and GitHub release correction paths.
    - [ ] 4.4.2.3 Subtask - Never test recovery by publishing or reverting a real version before approval.
