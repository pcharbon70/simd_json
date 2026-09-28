# Release-Candidate Review

Phase 6 produces a bounded internal review beneath
`_build/qualification/candidate-review`. Run the complete non-publishing gate
on Ubuntu 24.04 x86-64:

The resulting bundle is evidence, not authorization to publish.

```sh
bash scripts/ci/qualify_release_candidate.sh
```

`candidate-summary.env` binds version, proposed tag, commit, tree, archive and
NIF checksums, qualification fingerprint, supported toolchain, test count,
benchmark acceptance, licensing, publisher, recovery owner, security scan,
consumer result, and CI state. `gates.tsv` gives every pass, failure, pending
item, and its evidence path. `SHA256SUMS` covers these three bounded files.

The review deliberately excludes raw qualification logs, source JSON, process
identities, native addresses, and credentials. Experimental platforms and
deferred features are non-blocking only when they match the public support and
installation guides. A pending pull-request or main run, missing name/version
preflight, or absent explicit authorization keeps the candidate at no-go.

This command never tags, creates a GitHub Release, uploads an asset, publishes
to Hex, or changes package ownership.

## Explicit go/no-go

`scripts/release/review_go_no_go.sh` always writes the exact proposed version,
commit, tree, tag, package checksum, destination, and publish command. Its
default is `NO_GO`. A `GO` requires green pull-request and main run URLs, a
passed final name/version preflight, a loaded interactive credential, and an
unconditional owner decision whose six approved identity values exactly match
the evidence. Silence, conditional approval, pending or red CI, a missing
credential, or a changed source tree stays `NO_GO`. Any later source change
invalidates a prior decision and requires the complete qualification again.
