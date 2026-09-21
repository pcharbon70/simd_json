# Phase 7 — Version, Tag, Publish, and Post-Publish Verification

Back to plan: [README](./README.md)

- [ ] 7 Phase - Publish the explicitly approved first release, verify it as a
  user would, and activate the release subject only after external success.

## 7.1 Section — Final Release Commit and Tag

- [ ] 7.1 Section - Freeze one immutable release identity.
  - [ ] 7.1.1 Task - Prepare the release commit.
    - [ ] 7.1.1.1 Subtask - Set the approved semantic version and finalize its dated changelog entry.
    - [ ] 7.1.1.2 Subtask - Set ExDoc source ref, README dependency example, acceptance record, and package metadata to that version.
    - [ ] 7.1.1.3 Subtask - Merge through one reviewed PR and require green pull-request and resulting `main` CI before tagging.
  - [ ] 7.1.2 Task - Create the approved tag.
    - [ ] 7.1.2.1 Subtask - Re-run read-only preflight on synchronized clean `main` at the approved commit.
    - [ ] 7.1.2.2 Subtask - Create an annotated `v<version>` tag whose target equals the approved commit and push only that exact tag.
    - [ ] 7.1.2.3 Subtask - Verify local, origin, changelog, package, and source-ref identities match before publication.

## 7.2 Section — Explicit Hex Publication

- [ ] 7.2 Section - Perform the narrow externally mutating action.
  - [ ] 7.2.1 Task - Conduct final archive review.
    - [ ] 7.2.1.1 Subtask - Build from the tag, compare its checksum with approved evidence, and inspect included/excluded files and dependencies.
    - [ ] 7.2.1.2 Subtask - Recheck package-name/version availability and publisher identity immediately before submission.
    - [ ] 7.2.1.3 Subtask - Stop if Hex emits an unreviewed warning, recommendation, checksum change, or metadata difference.
  - [ ] 7.2.2 Task - Publish with explicit confirmation.
    - [ ] 7.2.2.1 Subtask - Invoke the approved `mix hex.publish` path from the clean tagged checkout without echoing credentials.
    - [ ] 7.2.2.2 Subtask - Record public package/version/checksum/owner identity and publication time, never the credential.
    - [ ] 7.2.2.3 Subtask - Do not republish, revert, retire, transfer ownership, or publish docs separately without a new explicit decision.

## 7.3 Section — Public Package and HexDocs Verification

- [ ] 7.3 Section - Verify the release from public infrastructure immediately.
  - [ ] 7.3.1 Task - Verify Hex and documentation.
    - [ ] 7.3.1.1 Subtask - Confirm package metadata, license, links, dependency constraints, owners, version, retirement state, and checksum through Hex.
    - [ ] 7.3.1.2 Subtask - Confirm HexDocs README, API modules, changelog, source links, operations, and acceptance pages load without warnings.
    - [ ] 7.3.1.3 Subtask - Compare downloaded tarball contents/checksum with the approved candidate.
  - [ ] 7.3.2 Task - Verify a real public consumer.
    - [ ] 7.3.2.1 Subtask - Create a new project, resolve `{:simd_json, "~> <version>"}` from public Hex, and compile from an empty project cache.
    - [ ] 7.3.2.2 Subtask - Run documented decode/select/stream smoke examples and verify native runtime diagnostics on the supported target.
    - [ ] 7.3.2.3 Subtask - Test that an unsupported environment receives the documented status or failure, not a false support claim.

## 7.4 Section — Observation, Recovery Decision, and Activation

- [ ] 7.4 Section - Close the milestone only after the first-release risk window.
  - [ ] 7.4.1 Task - Observe and triage.
    - [ ] 7.4.1.1 Subtask - Monitor Hex/HexDocs availability, install reports, CI, issue tracker, and security contact during the verified current recovery window.
    - [ ] 7.4.1.2 Subtask - Apply the pre-agreed severity criteria to keep, patch, revert, or retire the release.
    - [ ] 7.4.1.3 Subtask - Require explicit owner approval before any revert, retirement, republish, or ownership mutation.
  - [ ] 7.4.2 Task - Publish durable release records.
    - [ ] 7.4.2.1 Subtask - Create the GitHub release from the exact tag with changelog, support boundary, checksums, and installation link.
    - [ ] 7.4.2.2 Subtask - Add the accepted Milestone 6 record with public Hex/HexDocs identities and consumer verification evidence.
    - [ ] 7.4.2.3 Subtask - Activate the release subject, close all plan checkboxes, reconcile SpecLed/fingerprint state, and leave clean synchronized `main`.
