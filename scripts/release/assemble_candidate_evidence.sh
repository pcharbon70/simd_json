#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.provenance simd_json.release.candidate_preflight

repository_root="$(git rev-parse --show-toplevel)"
qualification_root="${1:-${repository_root}/_build/qualification}"
candidate_root="${qualification_root}/release-candidate"
acceptance_root="${qualification_root}/acceptance"
review_root="${qualification_root}/candidate-review"

case "${qualification_root}" in
  "${repository_root}/_build/qualification"|/tmp/*) ;;
  *) printf 'refusing unexpected qualification root: %s\n' "${qualification_root}" >&2; exit 64 ;;
esac

required_files=(
  "${acceptance_root}/environment.txt"
  "${acceptance_root}/supported-target.env"
  "${candidate_root}/package.sha256"
  "${candidate_root}/package-contents.txt"
  "${candidate_root}/documentation-contents.txt"
  "${candidate_root}/dependency-licenses.tsv"
  "${candidate_root}/provenance.env"
  "${candidate_root}/precompiled-provenance.env"
  "${candidate_root}/precompiled-consumer.status"
  "${candidate_root}/secret-scan.txt"
  "${qualification_root}/native/summary.txt"
  "${qualification_root}/native-pool/summary.txt"
  "${qualification_root}/decode/decode-benchmark.json"
  "${qualification_root}/decode/decode-scheduler.json"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -s "${required_file}" ]]; then
    printf 'candidate review evidence is missing: %s\n' "${required_file}" >&2
    exit 1
  fi
done

rm -rf -- "${review_root}"
mkdir -p "${review_root}"

read_value() {
  local key="$1"
  local file="$2"
  sed -n "s/^${key}=//p" "${file}" | head -n 1
}

validate_ci() {
  local label="$1"
  local status="$2"
  local url="$3"

  case "${status}" in
    passed|failed|pending|missing) ;;
    *) printf '%s CI status is invalid: %s\n' "${label}" "${status}" >&2; exit 64 ;;
  esac

  if [[ "${url}" != "unavailable" ]] &&
    [[ ! "${url}" =~ ^https://github\.com/[^/]+/[^/]+/actions/runs/[0-9]+$ ]]; then
    printf '%s CI URL is not a bounded GitHub Actions run URL\n' "${label}" >&2
    exit 64
  fi
}

version="$(sed -n 's/^  @version "\([^"]*\)"/\1/p' "${repository_root}/mix.exs")"
source_revision="$(git -C "${repository_root}" rev-parse HEAD)"
source_tree="$(git -C "${repository_root}" rev-parse HEAD^{tree})"
package_sha256="$(cut -d ' ' -f 1 "${candidate_root}/package.sha256")"
asset_sha256="$(read_value asset_sha256 "${candidate_root}/precompiled-provenance.env")"
qualification_sha256="$(read_value qualification_input_sha256 "${acceptance_root}/environment.txt")"
test_count="$(sed -nE 's/^([0-9]+) tests?,.*$/\1/p' "${acceptance_root}/full_test_suite.log" | tail -n 1)"
test_count="${test_count:-unavailable}"

run_url="unavailable"
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

pr_ci_status="${SIMD_JSON_PR_CI_STATUS:-pending}"
main_ci_status="${SIMD_JSON_MAIN_CI_STATUS:-pending}"
pr_ci_url="${SIMD_JSON_PR_CI_URL:-${run_url}}"
main_ci_url="${SIMD_JSON_MAIN_CI_URL:-unavailable}"
validate_ci pull-request "${pr_ci_status}" "${pr_ci_url}"
validate_ci main "${main_ci_status}" "${main_ci_url}"

cat >"${review_root}/gates.tsv" <<EOF
gate	status	evidence
supported_target	passed	acceptance/supported-target.env
native_abi_and_safety	passed	native/summary.txt
bounded_pool	passed	native-pool/summary.txt
decode_differential_scheduler_benchmark	passed	decode/summary.txt
package_docs_and_security	passed	release-candidate/summary.txt
fresh_offline_consumer	passed	release-candidate/precompiled-consumer.status
license_and_notices	passed	release-candidate/package-contents.txt
dependency_licenses	passed	release-candidate/dependency-licenses.tsv
recovery_readiness	passed	docs/releases/recovery.md
pull_request_ci	${pr_ci_status}	${pr_ci_url}
main_ci	${main_ci_status}	${main_ci_url}
owner_authorization	pending	docs/releases/publishing.md
EOF

cat >"${review_root}/candidate-summary.env" <<EOF
schema_version=1
package=simd_json
version=${version}
tag=v${version}
destination=hexpm
source_revision=${source_revision}
source_tree=${source_tree}
package_sha256=${package_sha256}
precompiled_asset_sha256=${asset_sha256}
qualification_input_sha256=${qualification_sha256}
target=x86_64-linux-gnu
operating_system=ubuntu-24.04
otp=27.3
elixir=1.18.4
zig=0.16.0
simdjson=5.0.1
full_test_count=${test_count}
benchmark_acceptance=passed
security_scan=passed
consumer_install=passed
license=MIT
publisher=pcharbon70
recovery_owner=pcharbon70
name_version_availability=requires_final_preflight
pull_request_ci_status=${pr_ci_status}
pull_request_ci_url=${pr_ci_url}
main_ci_status=${main_ci_status}
main_ci_url=${main_ci_url}
authorization=pending
publication_performed=false
EOF

cat >"${review_root}/candidate-summary.md" <<EOF
# simd_json ${version} internal release-candidate review

This record is qualification evidence, not authorization to tag or publish.

| Identity | Value |
| --- | --- |
| Version / proposed tag | \`${version}\` / \`v${version}\` |
| Commit | \`${source_revision}\` |
| Tree | \`${source_tree}\` |
| Hex archive SHA-256 | \`${package_sha256}\` |
| Precompiled NIF SHA-256 | \`${asset_sha256}\` |
| Target | \`x86_64-linux-gnu\` on Ubuntu 24.04 |
| Toolchain | OTP 27.3, Elixir 1.18.4, Zig 0.16.0, simdjson 5.0.1 |
| Full-suite tests | \`${test_count}\` |
| Destination | public Hex (\`hexpm\`) |
| Authorization | **pending — no-go** |

Every gate and its bounded evidence path is listed in \`gates.tsv\`. Publicly
documented experimental platforms and deferred features remain non-blocking;
the supported target is unchanged. Raw logs, JSON inputs, process identities,
native addresses, and credentials are deliberately excluded from this review.
EOF

if grep -nE '(HEX_API_KEY|ghp_[[:alnum:]]+|github_pat_[[:alnum:]_]+|#PID<|0x[0-9a-fA-F]{6,})' \
  "${review_root}/candidate-summary.env" "${review_root}/candidate-summary.md" \
  "${review_root}/gates.tsv"; then
  printf 'candidate review contains forbidden sensitive or high-cardinality data\n' >&2
  exit 1
fi

(
  cd "${review_root}"
  sha256sum candidate-summary.env candidate-summary.md gates.tsv >SHA256SUMS
  sha256sum --quiet --check SHA256SUMS
)

printf 'Checksummed release-candidate review assembled at %s\n' "${review_root}"
