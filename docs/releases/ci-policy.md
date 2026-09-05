# Release CI and Merge Policy

Release-preparation pull requests require both GitHub checks produced by the
cache matrix:

- `Native baseline (x86_64 Linux, cold)` proves the exact revision without a
  restored dependency, build, or Zigler cache.
- `Native baseline (x86_64 Linux, restored)` proves the same revision with the
  exact ABI-keyed cache restored.

Do not merge a release-preparation pull request while either check is pending,
failed, cancelled, skipped, or missing. The checks must report the same source
revision, Git tree, and qualification-input SHA-256. After merge, the exact
merge commit must pass both checks on the `main` push before release work may
continue.

Local qualification is useful supporting evidence and should be run before a
pull request, but it never substitutes for green GitHub CI on the pull-request
head and resulting `main` commit. Partial CI evidence is retained for failures;
successful jobs retain checksummed evidence for 30 days.

Repository branch-protection settings are an owner-controlled external
mutation. Enabling or changing required-check protection requires explicit
repository-owner authorization naming `main` and the exact check names above.
Milestone 6 Phase 2 documents that setting but does not change it without that
separate authorization.
