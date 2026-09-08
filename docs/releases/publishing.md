# Publisher Authentication and Workflow Boundary

The first `simd_json` publication uses an interactive, reviewed maintainer
session. CI publication is disabled. Repository qualification and a successful
preflight do not authorize a Hex mutation.

## Ownership record

The repository-only `release/publisher-policy.env` record names
the intended public `hexpm` repository, package name, confirmed publisher,
recovery owner and private recovery contact, and selected execution model. On
2026-09-08, the read-only `mix hex.user whoami` check confirmed the intended
publisher as `pcharbon70`. The same account is the pre-publication recovery
owner of record and its recovery contact matches `SECURITY.md`; Phase 6 must
verify public package ownership immediately after the first publication.

Run the read-only identity check without any publication key in the process:

```sh
unset HEX_API_KEY
bash scripts/release/verify_publisher.sh
```

The command refuses to run if `HEX_API_KEY` is present. It asks the installed
Hex client for the currently authenticated user and writes only non-secret,
checksummed identity evidence. It does not list, generate, revoke, or expose
keys and does not inspect shell history.

## Interactive first publication

The publishing maintainer must review one exact version, commit, tree, tag,
candidate SHA-256 digest, destination (`hexpm`), and proposed publication
command. Phase 6 requires a new explicit authorization naming all of those
values. Authentication occurs through Hex's interactive credential handling;
credentials must never appear in command arguments, terminal transcripts,
logs, artifacts, shell history, repository files, pull-request data, or
AI-visible output.

Preflight and publication remain separate invocations. No script in this phase
runs `mix hex.publish`, creates a tag, creates a GitHub release, or changes Hex
package owners. See the official [Hex publishing
guide](https://hex.pm/docs/publish) immediately before the release.

## Future CI publication boundary

CI publication remains prohibited unless the owner separately approves that
execution model. Any future automation must use manual dispatch with an exact
tag input, a protected release environment with required human approval,
read-only repository permissions, and no pull-request trigger or secret
access. Its publication credential must be short-lived and limited to the
`simd_json` package, stored only as a protected environment secret, never
printed, and revoked after the release. Adding such a workflow is a separately
reviewed change; this phase deliberately adds none.
