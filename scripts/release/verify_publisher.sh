#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.publisher_boundary simd_json.release.explicit_authorization

repository_root="$(git rev-parse --show-toplevel)"
policy_path="${repository_root}/release/publisher-policy.env"
default_evidence_root="${repository_root}/_build/qualification/publisher-identity"
evidence_root="${SIMD_JSON_PUBLISHER_EVIDENCE_DIR:-${default_evidence_root}}"

if [[ ${HEX_API_KEY+x} ]]; then
  printf 'publisher verification refuses to run while HEX_API_KEY is set\n' >&2
  exit 64
fi

policy_value() {
  local key="$1"
  awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; found=1} END {if (!found) exit 1}' \
    "${policy_path}"
}

if [[ "$(policy_value repository)" != "hexpm" ]] ||
  [[ "$(policy_value package)" != "simd_json" ]] ||
  [[ "$(policy_value publisher_type)" != "user" ]] ||
  [[ "$(policy_value execution_model)" != "interactive_reviewed" ]] ||
  [[ "$(policy_value ci_publication)" != "disabled" ]]; then
  printf 'publisher policy contains an unsupported publication boundary\n' >&2
  exit 1
fi

expected_publisher="$(policy_value publisher)"
recovery_owner="$(policy_value recovery_owner)"
recovery_contact="$(policy_value recovery_contact)"

if [[ -z "${expected_publisher}" || -z "${recovery_owner}" || -z "${recovery_contact}" ]]; then
  printf 'publisher policy is missing ownership or recovery identity\n' >&2
  exit 1
fi

actual_publisher="$(mix hex.user whoami | tail -n 1)"

if [[ "${actual_publisher}" != "${expected_publisher}" ]]; then
  printf 'authenticated Hex user does not match the publisher policy\n' >&2
  exit 1
fi

if [[ "${evidence_root}" == "${default_evidence_root}" ]]; then
  rm -rf -- "${evidence_root}"
elif [[ -e "${evidence_root}" ]] &&
  [[ -n "$(find "${evidence_root}" -mindepth 1 -print -quit)" ]]; then
  printf 'publisher evidence directory is not empty: %s\n' "${evidence_root}" >&2
  exit 64
fi

mkdir -p "${evidence_root}"

{
  printf 'schema_version=1\n'
  printf 'repository=hexpm\n'
  printf 'package=simd_json\n'
  printf 'publisher=%s\n' "${expected_publisher}"
  printf 'recovery_owner=%s\n' "${recovery_owner}"
  printf 'execution_model=interactive_reviewed\n'
  printf 'ci_publication=disabled\n'
  printf 'credential_loaded=false\n'
  printf 'verification=passed\n'
} >"${evidence_root}/publisher.env"

(
  cd "${evidence_root}"
  sha256sum publisher.env >SHA256SUMS
)

printf 'Verified interactive Hex publisher identity without loading a publication key\n'
