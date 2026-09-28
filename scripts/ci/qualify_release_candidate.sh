#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.green_ci simd_json.release.candidate_preflight

repository_root="$(git rev-parse --show-toplevel)"
qualification_root="${repository_root}/_build/qualification"
acceptance_root="${qualification_root}/acceptance"

cd "${repository_root}"

if [[ "$(uname -m)" != "x86_64" ]]; then
  printf 'release-candidate qualification requires x86_64, got %s\n' "$(uname -m)" >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]] ||
  ! grep -Eq '^ID=ubuntu$' /etc/os-release ||
  ! grep -Eq '^VERSION_ID="?24\.04"?$' /etc/os-release; then
  printf 'release-candidate qualification requires Ubuntu 24.04\n' >&2
  exit 1
fi

source_revision="$(git rev-parse HEAD)"
source_tree="$(git rev-parse HEAD^{tree})"

bash scripts/ci/qualify_milestone_5.sh

for evidence in \
  "${qualification_root}/native/summary.txt" \
  "${qualification_root}/native-pool/saturation.json" \
  "${qualification_root}/decode/decode-benchmark.json" \
  "${qualification_root}/decode/decode-scheduler.json" \
  "${qualification_root}/release-candidate/reproducibility.env" \
  "${qualification_root}/release-candidate/precompiled-provenance.env" \
  "${qualification_root}/release-candidate/precompiled-consumer.status"; do
  if [[ ! -s "${evidence}" ]]; then
    printf 'release-candidate qualification is missing evidence: %s\n' "${evidence}" >&2
    exit 1
  fi
done

grep -Fxq 'archive_reproducible=true' \
  "${qualification_root}/release-candidate/reproducibility.env"
grep -Fxq 'reproducible=true' \
  "${qualification_root}/release-candidate/precompiled-provenance.env"
grep -Fxq 'zig_free_consumer=passed' \
  "${qualification_root}/release-candidate/precompiled-consumer.status"

recorded_revision="$(sed -n 's/^source_revision=//p' "${acceptance_root}/environment.txt")"
recorded_tree="$(sed -n 's/^source_tree=//p' "${acceptance_root}/environment.txt")"
if [[ "${recorded_revision}" != "${source_revision}" ]] ||
  [[ "${recorded_tree}" != "${source_tree}" ]]; then
  printf 'qualification evidence does not match the candidate source identity\n' >&2
  exit 1
fi

{
  printf 'status=passed\n'
  printf 'target=x86_64-linux-gnu\n'
  printf 'operating_system=ubuntu-24.04\n'
  printf 'source_revision=%s\n' "${source_revision}"
  printf 'source_tree=%s\n' "${source_tree}"
  printf 'independent_native_build_roots=2\n'
  printf 'archive_build_roots=2\n'
  printf 'pr_and_main_checks=required\n'
  printf 'publication_authorized=false\n'
} >"${acceptance_root}/supported-target.env"

(
  cd "${qualification_root}"
  find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >SHA256SUMS
)

printf 'Phase 6 supported-target release-candidate qualification passed\n'
