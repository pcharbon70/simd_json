# Release Preflight

<!-- covers: simd_json.release.read_only_preflight simd_json.release.candidate_preflight -->

The first public release starts with a read-only preflight. It proves release
identity and local evidence without creating a commit, branch, tag, GitHub
release, package owner, or Hex release.

## Preconditions

Run the command only from a clean `main` checkout. `HEAD`, the local
`origin/main` tracking ref, and the live remote `refs/heads/main` value must be
the same commit. The worktree may not contain staged, modified, or untracked
files. The command queries live refs with `git ls-remote`; it deliberately does
not fetch or modify a Git ref.

No publication credential belongs in a preflight process. Remove any inherited
publication key before running it:

~~~console
unset HEX_API_KEY
bash scripts/release/preflight.sh 0.1.0 v0.1.0
~~~

The positional values are mandatory. The tag must be exactly `vVERSION`. The
command rejects an existing local tag, an existing remote tag, and an existing
public Hex release. Hex availability is checked through the unauthenticated
public release endpoint; the command never reads Hex ownership or key data.

## Composed proof

The preflight bootstraps the pinned release tools and then runs:

1. strict formatter verification;
2. strict HTML documentation generation;
3. the package inventory, metadata, size, secret, checksum, and link gate;
4. the checked-in native qualification-fingerprint freshness gate; and
5. strict structural SpecLed validation written to a temporary state file.

The package verifier uses Hex's deliberately unauthenticated dry-run guard, but
there is no command in this procedure that can create or replace a public
release. Full release-candidate qualification remains a separate Phase 5 gate.

## Evidence

By default, evidence is written beneath
`_build/release/preflight/vVERSION-PID`. Automation may set
`SIMD_JSON_PREFLIGHT_REPORT_DIR` to one new or empty directory. The bounded
`preflight.env` report records only fixed non-secret fields: result, failed
gate, package, version, tag, commit, tree, remote-main commit, native
qualification fingerprint, package checksum, lock checksum, completion time,
and exit status. `SHA256SUMS` binds the report and its logs.

Any failed gate invalidates the preflight. Correct the source or external
identity, create a new clean commit when appropriate, synchronize `main`, and
run the complete command again.
