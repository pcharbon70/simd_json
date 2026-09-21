#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.provenance simd_json.release.recovery_readiness

if [[ $# -ne 1 ]]; then
  printf 'usage: verify_candidate_evidence.sh EVIDENCE_DIRECTORY\n' >&2
  exit 64
fi

evidence_root="$1"

for required_file in \
  simd_json-0.1.0.tar \
  documentation-contents.txt \
  native-compile.status \
  precompiled-provenance.env \
  precompiled-consumer.status \
  secret-scan.txt \
  provenance.env \
  SHA256SUMS; do
  if [[ ! -s "${evidence_root}/${required_file}" ]]; then
    printf 'candidate evidence is missing %s\n' "${required_file}" >&2
    exit 1
  fi
done

precompiled_asset="$(sed -n 's/^asset=//p' "${evidence_root}/precompiled-provenance.env")"
precompiled_sha256="$(sed -n 's/^asset_sha256=//p' "${evidence_root}/precompiled-provenance.env")"

if [[ "${precompiled_asset}" != "simd_json-v0.1.0-x86_64-linux-gnu.so" ]] ||
  [[ ! "${precompiled_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
  printf 'candidate precompiled provenance has an invalid asset identity\n' >&2
  exit 1
fi

if [[ ! -s "${evidence_root}/${precompiled_asset}" ]]; then
  printf 'candidate evidence is missing precompiled asset %s\n' \
    "${precompiled_asset}" >&2
  exit 1
fi

actual_precompiled_sha256="$(sha256sum "${evidence_root}/${precompiled_asset}" | cut -d ' ' -f 1)"
if [[ "${actual_precompiled_sha256}" != "${precompiled_sha256}" ]]; then
  printf 'candidate precompiled asset checksum does not match provenance\n' >&2
  exit 1
fi

for expected_precompiled_status in \
  'status=passed' \
  'zig_free_consumer=passed' \
  'download_failure_handling=passed'; do
  if ! grep -Fxq "${expected_precompiled_status}" \
    "${evidence_root}/precompiled-consumer.status"; then
    printf 'candidate precompiled consumer status is missing %s\n' \
      "${expected_precompiled_status}" >&2
    exit 1
  fi
done

if ! grep -Fxq 'index.html' "${evidence_root}/documentation-contents.txt"; then
  printf 'candidate documentation does not contain index.html\n' >&2
  exit 1
fi

if ! grep -Fxq 'status=passed' "${evidence_root}/native-compile.status"; then
  printf 'candidate native compilation did not pass\n' >&2
  exit 1
fi

if grep -nE '=matched$' "${evidence_root}/secret-scan.txt"; then
  printf 'candidate secret scan reports a possible credential\n' >&2
  exit 1
fi

for expected_provenance in \
  'source_state=clean' \
  'archive_reproducible=true' \
  'normalized_contents_equal=true'; do
  if ! grep -Fxq "${expected_provenance}" "${evidence_root}/provenance.env"; then
    printf 'candidate provenance is missing %s\n' "${expected_provenance}" >&2
    exit 1
  fi
done

if ! (cd "${evidence_root}" && sha256sum --quiet --check SHA256SUMS); then
  printf 'candidate evidence checksum verification failed\n' >&2
  exit 1
fi

printf 'Candidate evidence verification passed\n'
