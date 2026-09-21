# Release Recovery and Retirement Runbook

This runbook is prepared before publication so incident choices do not depend
on improvisation. It does not authorize a real revert, replacement,
retirement, key revocation, tag change, or GitHub release mutation.

## Reverify the current window

The following public Hex behavior was checked against the installed Hex 2.2.2
task help and the official [publishing guide](https://hex.pm/docs/publish) on
2026-09-08:

- A newly created package can be updated or reverted for 24 hours after its
  initial publication. Reverting its last version removes the package.
- A new version of an existing package can be updated or reverted for one
  hour.
- Documentation can be updated without those time limits.
- A retired version remains resolvable and usable, but Hex flags it and shows
  the retirement message.

Hex policy and tooling can change. The release owner must re-read the current
official Hex publishing, [retirement](https://hexdocs.pm/hex/Mix.Tasks.Hex.Retire.html),
and [ownership](https://hexdocs.pm/hex/Mix.Tasks.Hex.Owner.html) documentation
immediately before publication and record the observed deadline.

## Authority and contacts

`pcharbon70` is the release decision-maker and recovery owner of record. Private
incident contact is `pcharbon70@gmail.com`, as published in `SECURITY.md`. The
release owner records the exact version, observed publication time, remaining
revert window, candidate digest, defect, user impact, and chosen action. A
source or artifact change requires a new qualified candidate; urgency does not
permit republishing unreviewed bytes.

## Decision table

| Incident | Inside current revert window | Outside the window |
| --- | --- | --- |
| Missing or broken docs only | Correct and republish docs after verifying the package archive is unchanged. | Republish docs; their correction is not constrained by the package revert window. |
| Precompiled NIF asset missing or download unavailable | Stop Hex publication if it has not happened. If Hex is public, restore only the originally approved bytes and digest when possible; otherwise revert the exact Hex version. | Publish a newly qualified patch and retire the broken version as `invalid` when users must be warned. |
| Precompiled NIF asset replaced or checksum mismatch | Preserve both observed bytes and metadata, stop promotion, and treat replacement as a release-integrity incident. Never change the package checksum to bless replacement bytes. | Retire the version, publish a newly qualified patch, and investigate as a security incident. |
| Explicit source-build failure on the supported target | Do not use it as an automatic consumer fallback; repair and requalify the artifact pipeline. | Publish a qualified patch if the documented audit path must be restored. |
| Public checksum differs from the approved archive | Stop promotion, preserve evidence, and revert the exact version while investigating. | Retire the version, publish a newly qualified patch, and treat unexplained alteration as a security incident. |
| Publication credential or packaged secret exposed | Revoke/rotate the credential first, preserve evidence, assess access, and revert if the package is affected. | Revoke/rotate first, open a private advisory, retire as `security` when needed, and publish a qualified patch. |
| Compatible non-critical defect | Prefer a qualified patch if leaving the version available is safe. | Publish a qualified patch; retire only when continued use should be discouraged. |

Revert removes the public version and is preferred for a materially wrong
release while Hex still permits it. A patch preserves history and is preferred
when the affected version can safely remain available. Retirement is the
durable warning when the window has closed or removal would be inappropriate.

## Command examples requiring confirmation

These are reference templates, not release scripts. Before any command, obtain
explicit confirmation for the exact version and desired external state, replace
every placeholder, echo the resolved non-secret identity for review, and stop
if the current Hex policy differs.

```sh
VERSION='<exact-version>'
TAG="v${VERSION}"

# Revert the exact Hex release while the verified window is open.
mix hex.publish --revert "$VERSION"

# Documentation-only correction; rebuild and inspect docs first.
mix hex.publish docs

# Durable warning after the removal window or when history should remain.
mix hex.retire simd_json "$VERSION" invalid --message '<reviewed message>'

# Revoke a specifically identified compromised key before other remediation.
mix hex.user key revoke KEY_NAME

# Correct release metadata, or remove an unpublished/broken release object.
# Never replace an asset in place after Hex references its committed digest.
gh release edit "$TAG" --notes-file '<reviewed-notes-file>'
gh release delete "$TAG"
```

Do not delete or move the Git tag merely to conceal a released artifact. A tag
correction needs a separate exact-state decision and a written explanation.
Owner changes use the documented `mix hex.owner` flow and likewise require
explicit authorization.

For suspected vulnerability or credential exposure, start with the private
security contact and create a private GitHub Security Advisory at the
repository's Security / Advisories page. Coordinate disclosure only after
credential containment, impact assessment, and a qualified remediation.

## Non-mutating rehearsal

Run:

```sh
bash scripts/release/rehearse_recovery.sh
```

The rehearsal creates only temporary synthetic evidence. It proves that the
candidate verifier rejects missing documentation, a failed native compilation,
an archive checksum mismatch, a secret-scan match, a missing precompiled asset,
replacement bytes, a mismatched recorded asset digest, and a simulated download
failure. It also verifies that the owner contact, credential-revocation,
private-advisory, and GitHub release correction paths are recorded. It never
contacts Hex or GitHub and never publishes, replaces, reverts, retires, or
deletes a real release.
