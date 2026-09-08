#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.recovery_readiness simd_json.release.explicit_authorization

repository_root="$(git rev-parse --show-toplevel)"
default_evidence_root="${repository_root}/_build/qualification/recovery-rehearsal"
evidence_root="${SIMD_JSON_RECOVERY_EVIDENCE_DIR:-${default_evidence_root}}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-recovery.XXXXXX")"
verifier="${repository_root}/scripts/release/verify_candidate_evidence.sh"

cleanup() {
  local original_status=$?

  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"
  return "${original_status}"
}

trap cleanup EXIT

if [[ "${evidence_root}" == "${default_evidence_root}" ]]; then
  rm -rf -- "${evidence_root}"
elif [[ -e "${evidence_root}" ]] &&
  [[ -n "$(find "${evidence_root}" -mindepth 1 -print -quit)" ]]; then
  printf 'recovery evidence directory is not empty: %s\n' "${evidence_root}" >&2
  exit 64
fi

mkdir -p "${evidence_root}"
cd "${repository_root}"

write_checksums() {
  local root="$1"

  (
    cd "${root}"
    find . -type f ! -name SHA256SUMS -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum >SHA256SUMS
  )
}

baseline="${scratch_root}/baseline"
mkdir -p "${baseline}"
printf 'synthetic candidate archive\n' >"${baseline}/simd_json-0.1.0.tar"
printf 'index.html\nSimdJson.html\n' >"${baseline}/documentation-contents.txt"
printf 'status=passed\n' >"${baseline}/native-compile.status"
printf 'hex_dry_run=passed\nprivate_key=clear\n' >"${baseline}/secret-scan.txt"
{
  printf 'source_state=clean\n'
  printf 'archive_reproducible=true\n'
  printf 'normalized_contents_equal=true\n'
} >"${baseline}/provenance.env"
write_checksums "${baseline}"
"${verifier}" "${baseline}" >"${evidence_root}/baseline.log"

expect_failure() {
  local scenario="$1"
  local fixture="$2"

  if "${verifier}" "${fixture}" >"${evidence_root}/${scenario}.log" 2>&1; then
    printf 'recovery rehearsal failed to detect %s\n' "${scenario}" >&2
    exit 1
  fi

  printf '%s=detected\n' "${scenario}" >>"${evidence_root}/rehearsal.env"
}

missing_docs="${scratch_root}/missing-docs"
cp -a "${baseline}" "${missing_docs}"
rm -f -- "${missing_docs}/documentation-contents.txt"
expect_failure missing_docs "${missing_docs}"

broken_native="${scratch_root}/broken-native"
cp -a "${baseline}" "${broken_native}"
printf 'status=failed\n' >"${broken_native}/native-compile.status"
write_checksums "${broken_native}"
expect_failure broken_native_compile "${broken_native}"

checksum_mismatch="${scratch_root}/checksum-mismatch"
cp -a "${baseline}" "${checksum_mismatch}"
printf 'corruption\n' >>"${checksum_mismatch}/simd_json-0.1.0.tar"
expect_failure checksum_mismatch "${checksum_mismatch}"

leaked_secret="${scratch_root}/leaked-secret"
cp -a "${baseline}" "${leaked_secret}"
printf 'private_key=matched\n' >>"${leaked_secret}/secret-scan.txt"
write_checksums "${leaked_secret}"
expect_failure leaked_secret "${leaked_secret}"

grep -Fq 'recovery_owner=pcharbon70' release/publisher-policy.env
grep -Fq 'pcharbon70@gmail.com' SECURITY.md
grep -Fq 'mix hex.user key revoke KEY_NAME' docs/releases/recovery.md
grep -Fq 'GitHub Security Advisory' docs/releases/recovery.md
grep -Fq 'gh release edit "$TAG"' docs/releases/recovery.md

{
  printf 'owner_contact=verified\n'
  printf 'credential_revocation=verified\n'
  printf 'security_advisory=verified\n'
  printf 'github_release_correction=verified\n'
  printf 'external_mutation=none\n'
} >>"${evidence_root}/rehearsal.env"

(
  cd "${evidence_root}"
  find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >SHA256SUMS
)

printf 'Recovery rehearsal passed without mutating Hex or GitHub\n'
