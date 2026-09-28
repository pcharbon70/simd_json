#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.explicit_authorization simd_json.release.candidate_preflight

repository_root="$(git rev-parse --show-toplevel)"
qualification_root="${1:-${repository_root}/_build/qualification}"
review_root="${qualification_root}/candidate-review"
summary="${review_root}/candidate-summary.env"
gates="${review_root}/gates.tsv"
decision_file="${review_root}/go-no-go.env"
proposal_file="${review_root}/go-no-go.md"
policy="${repository_root}/release/publisher-policy.env"

for required_file in "${summary}" "${gates}" "${policy}" \
  "${repository_root}/LICENSE" "${repository_root}/THIRD_PARTY_NOTICES.md" \
  "${repository_root}/CHANGELOG.md" "${repository_root}/SECURITY.md" \
  "${repository_root}/docs/releases/recovery.md"; do
  if [[ ! -s "${required_file}" ]]; then
    printf 'go/no-go review is missing required evidence: %s\n' "${required_file}" >&2
    exit 1
  fi
done

read_value() {
  local key="$1"
  local file="$2"
  sed -n "s/^${key}=//p" "${file}" | head -n 1
}

version="$(read_value version "${summary}")"
tag="$(read_value tag "${summary}")"
source_revision="$(read_value source_revision "${summary}")"
source_tree="$(read_value source_tree "${summary}")"
package_sha256="$(read_value package_sha256 "${summary}")"
destination="$(read_value destination "${summary}")"
pr_ci_status="$(read_value pull_request_ci_status "${summary}")"
main_ci_status="$(read_value main_ci_status "${summary}")"
availability="$(read_value name_version_availability "${summary}")"
publisher="$(read_value publisher "${policy}")"
recovery_owner="$(read_value recovery_owner "${policy}")"
ci_publication="$(read_value ci_publication "${policy}")"
publish_command="mix hex.publish package"
requested_decision="${SIMD_JSON_RELEASE_DECISION:-SILENCE}"
credential_loaded=false
if [[ -n "${HEX_API_KEY:-}" ]]; then credential_loaded=true; fi

reasons=()
[[ "${requested_decision}" == "GO" ]] || reasons+=("explicit_unconditional_go_missing")
[[ "${pr_ci_status}" == "passed" ]] || reasons+=("pull_request_ci_${pr_ci_status:-missing}")
[[ "${main_ci_status}" == "passed" ]] || reasons+=("main_ci_${main_ci_status:-missing}")
[[ "${availability}" == "passed" ]] || reasons+=("name_version_availability_${availability:-missing}")
[[ "${credential_loaded}" == "true" ]] || reasons+=("publication_credential_missing")
[[ "${ci_publication}" == "disabled" ]] || reasons+=("ci_publication_policy_changed")
[[ -n "${publisher}" && -n "${recovery_owner}" ]] || reasons+=("publisher_or_recovery_owner_missing")

current_revision="$(git -C "${repository_root}" rev-parse HEAD)"
current_tree="$(git -C "${repository_root}" rev-parse HEAD^{tree})"
[[ "${current_revision}" == "${source_revision}" ]] || reasons+=("source_revision_changed")
[[ "${current_tree}" == "${source_tree}" ]] || reasons+=("source_tree_changed")
[[ -z "$(git -C "${repository_root}" status --porcelain=v1 --untracked-files=all)" ]] ||
  reasons+=("worktree_changed")

[[ "${SIMD_JSON_APPROVED_VERSION:-}" == "${version}" ]] || reasons+=("approved_version_mismatch")
[[ "${SIMD_JSON_APPROVED_COMMIT:-}" == "${source_revision}" ]] || reasons+=("approved_commit_mismatch")
[[ "${SIMD_JSON_APPROVED_TAG:-}" == "${tag}" ]] || reasons+=("approved_tag_mismatch")
[[ "${SIMD_JSON_APPROVED_PACKAGE_SHA256:-}" == "${package_sha256}" ]] ||
  reasons+=("approved_package_checksum_mismatch")
[[ "${SIMD_JSON_APPROVED_DESTINATION:-}" == "${destination}" ]] ||
  reasons+=("approved_destination_mismatch")
[[ "${SIMD_JSON_APPROVED_PUBLISH_COMMAND:-}" == "${publish_command}" ]] ||
  reasons+=("approved_publish_command_mismatch")

decision="NO_GO"
if ((${#reasons[@]} == 0)); then decision="GO"; fi

reason_csv="none"
if ((${#reasons[@]} > 0)); then
  reason_csv="$(IFS=,; printf '%s' "${reasons[*]}")"
fi

cat >"${decision_file}" <<EOF
schema_version=1
decision=${decision}
reasons=${reason_csv}
version=${version}
commit=${source_revision}
tree=${source_tree}
tag=${tag}
package_sha256=${package_sha256}
destination=${destination}
publish_command=${publish_command}
publisher=${publisher}
recovery_owner=${recovery_owner}
pull_request_ci_status=${pr_ci_status}
main_ci_status=${main_ci_status}
credential_loaded=${credential_loaded}
source_change_invalidates_approval=true
publication_performed=false
EOF

cat >"${proposal_file}" <<EOF
# Release go/no-go: ${decision}

| Approval field | Exact value |
| --- | --- |
| Version | \`${version}\` |
| Commit | \`${source_revision}\` |
| Tree | \`${source_tree}\` |
| Tag | \`${tag}\` |
| Package SHA-256 | \`${package_sha256}\` |
| Destination | \`${destination}\` |
| Publish command | \`${publish_command}\` |
| Decision | **${decision}** |
| Reasons | \`${reason_csv}\` |

No tag, GitHub Release, asset upload, Hex publication, or ownership mutation
was performed. Silence, conditional approval, red or pending CI, a missing
credential, or any source change is a no-go. Any change after a GO invalidates
the decision and requires complete requalification.
EOF

(
  cd "${review_root}"
  sha256sum go-no-go.env go-no-go.md >GO_NO_GO_SHA256SUMS
  sha256sum --quiet --check GO_NO_GO_SHA256SUMS
)

printf 'Release decision: %s\n' "${decision}"
printf 'Review: %s\n' "${proposal_file}"
