# Phase 1 — Release Contract, Licensing, and Package Identity

Back to plan: [README](./README.md)

- [ ] 1 Phase - Freeze the legal, ownership, compatibility, and package
  identity contract before modifying publication tooling.

## 1.1 Section — Distribution and Package Identity

- [ ] 1.1 Section - Decide exactly what and where the first release publishes.
  - [ ] 1.1.1 Task - Freeze the public package identity.
    - [ ] 1.1.1.1 Subtask - Confirm public Hex rather than a private organization repository.
    - [ ] 1.1.1.2 Subtask - Recheck that `simd_json` is unclaimed immediately before reserving or publishing it.
    - [ ] 1.1.1.3 Subtask - Keep OTP application `:simd_json`, Hex package `simd_json`, and `SimdJson.*` module ownership aligned.
  - [ ] 1.1.2 Task - Freeze the first-version policy.
    - [ ] 1.1.2.1 Subtask - Confirm `0.1.0` as the first public version or record an owner-selected alternative.
    - [ ] 1.1.2.2 Subtask - Require semantic versioning and minor-version increments for breaking changes while major version is zero.
    - [ ] 1.1.2.3 Subtask - Define whether release candidates use Git tags only or a separate prerelease version.

## 1.2 Section — Project License and Third-Party Notices

- [ ] 1.2 Section - Establish an explicit license for wrapper code without
  conflating it with vendored dependency licenses.
  - [ ] 1.2.1 Task - Obtain and record the repository owner's license choice.
    - [ ] 1.2.1.1 Subtask - Choose Apache-2.0, MIT, or an explicitly reviewed dual-license expression.
    - [ ] 1.2.1.2 Subtask - Add the complete root `LICENSE` file or files and copyright holder/year.
    - [ ] 1.2.1.3 Subtask - Make `mix.exs`, README, Hex metadata, and SPDX wording match the chosen grant exactly.
  - [ ] 1.2.2 Task - Preserve third-party attribution.
    - [ ] 1.2.2.1 Subtask - Retain both vendored simdjson license files and source provenance.
    - [ ] 1.2.2.2 Subtask - Add a `NOTICE` or third-party section when required by the chosen license review.
    - [ ] 1.2.2.3 Subtask - Test that project and third-party licenses are present in the unpacked Hex archive.

## 1.3 Section — Supported Target and Compatibility Promise

- [ ] 1.3 Section - Convert milestone acceptance into a public support policy.
  - [ ] 1.3.1 Task - Freeze the supported environment.
    - [ ] 1.3.1.1 Subtask - Claim only Ubuntu 24.04 x86-64, OTP 27.3, Elixir 1.18.4, Zig 0.16.0, Zigler 0.16.0, and simdjson 4.6.9.
    - [ ] 1.3.1.2 Subtask - Label other operating systems, architectures, OTP/Elixir versions, and CPU dispatch paths experimental or unsupported.
    - [ ] 1.3.1.3 Subtask - Define the evidence required to add another supported target.
  - [ ] 1.3.2 Task - Freeze public limitations.
    - [ ] 1.3.2.1 Subtask - State the binary-only input and source-build requirements.
    - [ ] 1.3.2.2 Subtask - State that select/stream avoid full decoded-tree allocation but still retain the complete encoded input binary.
    - [ ] 1.3.2.3 Subtask - Link duplicate-key, number-range, cancellation, saturation, and option differences to their accepted records.

## 1.4 Section — Release Decision and Specification Baseline

- [ ] 1.4 Section - Add durable current-truth ownership for publication.
  - [ ] 1.4.1 Task - Add a publication and versioning ADR.
    - [ ] 1.4.1.1 Subtask - Record package destination, identity, licensing, support, credential boundary, and approval ownership.
    - [ ] 1.4.1.2 Subtask - Record that publish, tag, revert, retire, and owner changes are explicit external actions.
  - [ ] 1.4.2 Task - Add a planned release subject.
    - [ ] 1.4.2.1 Subtask - Define package, docs, provenance, CI, authorization, publication, and verification requirements.
    - [ ] 1.4.2.2 Subtask - Add a complete bootstrap exception until Phase 6 succeeds.
    - [ ] 1.4.2.3 Subtask - Run format, SpecLed index/validate/impact, and qualification-fingerprint checks.
