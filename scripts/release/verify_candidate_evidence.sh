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
  secret-scan.txt \
  provenance.env \
  SHA256SUMS; do
  if [[ ! -s "${evidence_root}/${required_file}" ]]; then
    printf 'candidate evidence is missing %s\n' "${required_file}" >&2
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
