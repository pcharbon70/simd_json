# Release Archive Provenance

Milestone 6 binds the exact Hex archive and precompiled NIF reviewed for
release to one committed source tree. This evidence is qualification input,
not authorization to publish.

## Build the candidate

Run the package gate from a clean committed checkout:

```sh
SIMD_JSON_REQUIRE_CLEAN_CANDIDATE=1 \
  bash scripts/ci/verify_package_documentation.sh
```

The gate builds `simd_json-0.1.0.tar` twice in separate temporary directories.
It requires both unpacked file manifests and both complete archive SHA-256
digests to match. The normalized manifest records each path, file mode, byte
size, and content digest. Exact archive equality means there are currently no
accepted nondeterministic fields; `reproducibility.env` records
`nondeterministic_fields=none` and the gate fails instead of normalizing away a
difference.

## Evidence identity

The default evidence directory is `_build/qualification/package-documentation`.
`provenance.env` records the package and version, proposed tag, Git commit and
tree, clean-worktree state, `mix.lock` and `.tool-versions` digests, qualified
target, native qualification-input fingerprint, candidate archive digest,
normalized source-manifest digest, dependency-inventory digest, and both
reproducibility results.

`dependency-licenses.tsv` inventories the wrapper, vendored simdjson, and every
non-optional transitive Hex dependency resolved from the archive metadata and
the dependency metadata under `deps`. `package-contents.txt`,
`package-files.normalized.tsv`, and `package-files.sha256` provide the source
inventory. `SHA256SUMS` covers every retained evidence file, including the
exact candidate archive.

The precompiled artifact builder independently produces the release-safe NIF
twice, strips non-runtime sections, and requires byte identity. Its
`provenance.env` binds the asset name and digest to the source commit and tree,
Zig and strip versions, target, native fingerprint, dynamic-dependency policy,
and sole exported symbol. The committed checksum manifest must match that
candidate. The Hex archive contains this checksum and all source inputs, but no
generated `.so`; the binary is retained separately as a CI artifact and later
uploaded unchanged to the matching GitHub release.

The aggregate qualification command places this directory at
`_build/qualification/release-candidate`. GitHub Actions uploads the enclosing
`_build/qualification` tree as
`milestone-6-release-qualification-<cache-mode>-<commit>` for a fixed 30-day
retention period. The commit-qualified artifact name and checksums make review
unambiguous; downloading an artifact never makes it publishable without the
later qualification and explicit authorization gates.
