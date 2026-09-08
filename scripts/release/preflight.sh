#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.release.read_only_preflight simd_json.release.candidate_preflight

usage() {
  printf 'usage: %s VERSION TAG\n' "${0##*/}" >&2
  printf 'example: %s 0.1.0 v0.1.0\n' "${0##*/}" >&2
}

if [[ $# -ne 2 ]]; then
  usage
  exit 64
fi

version="$1"
tag="$2"

if [[ ! "${version}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  printf 'release version is not a plain semantic version: %s\n' "${version}" >&2
  exit 64
fi

if [[ "${tag}" != "v${version}" ]]; then
  printf 'release tag must be exactly v%s; received %s\n' "${version}" "${tag}" >&2
  exit 64
fi

if [[ -n "${HEX_API_KEY:-}" ]]; then
  printf 'release preflight refuses to run while HEX_API_KEY is set\n' >&2
  exit 64
fi

repository_root="$(git rev-parse --show-toplevel)"
release_mix_env="${SIMD_JSON_RELEASE_MIX_ENV:-test}"
report_root="${SIMD_JSON_PREFLIGHT_REPORT_DIR:-${repository_root}/_build/release/preflight/${tag}-$$}"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/simd-json-release-preflight.XXXXXX")"
current_gate="initialization"
preflight_status="failed"
source_revision="unavailable"
source_tree="unavailable"
origin_main="unavailable"
qualification_input_sha256="unavailable"
package_sha256="unavailable"

cleanup() {
  local original_status=$?

  chmod -R u+w "${scratch_root}" 2>/dev/null || true
  rm -rf -- "${scratch_root}"
  return "${original_status}"
}

write_report() {
  local exit_status="$1"
  local completed_at failed_gate

  completed_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  failed_gate="${current_gate}"
  if [[ "${preflight_status}" == "passed" ]]; then
    failed_gate="none"
  fi

  {
    printf 'schema_version=1\n'
    printf 'status=%s\n' "${preflight_status}"
    printf 'failed_gate=%s\n' "${failed_gate}"
    printf 'package=simd_json\n'
    printf 'version=%s\n' "${version}"
    printf 'tag=%s\n' "${tag}"
    printf 'source_revision=%s\n' "${source_revision}"
    printf 'source_tree=%s\n' "${source_tree}"
    printf 'origin_main=%s\n' "${origin_main}"
    printf 'qualification_input_sha256=%s\n' "${qualification_input_sha256}"
    printf 'package_sha256=%s\n' "${package_sha256}"
    printf 'mix_lock_sha256=%s\n' "$(sha256sum "${repository_root}/mix.lock" | cut -d ' ' -f 1)"
    printf 'completed_at=%s\n' "${completed_at}"
    printf 'exit_status=%s\n' "${exit_status}"
  } >"${report_root}/preflight.env"

  (
    cd "${report_root}"
    find . -type f ! -name SHA256SUMS -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum >SHA256SUMS
  )
}

finish() {
  local original_status=$?

  write_report "${original_status}"
  cleanup
  return "${original_status}"
}

if [[ -e "${report_root}" ]] &&
  [[ -n "$(find "${report_root}" -mindepth 1 -print -quit)" ]]; then
  printf 'preflight report directory is not empty: %s\n' "${report_root}" >&2
  cleanup
  exit 64
fi

mkdir -p "${report_root}/logs"
trap finish EXIT
cd "${repository_root}"

run_step() {
  local name="$1"
  shift

  current_gate="${name}"
  printf '%q ' "$@" >"${report_root}/logs/${name}.command"
  printf '\n' >>"${report_root}/logs/${name}.command"
  "$@" >"${report_root}/logs/${name}.log" 2>&1
}

current_gate="repository_identity"
branch="$(git symbolic-ref --quiet --short HEAD)"
if [[ "${branch}" != "main" ]]; then
  printf 'release preflight requires branch main; received %s\n' "${branch}" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  printf 'release preflight requires a clean worktree with no untracked files\n' >&2
  exit 1
fi

source_revision="$(git rev-parse HEAD)"
source_tree="$(git rev-parse 'HEAD^{tree}')"
origin_main="$(git rev-parse origin/main)"
remote_main="$(git ls-remote --heads origin refs/heads/main | cut -f 1)"

if [[ -z "${remote_main}" ]]; then
  printf 'origin/main was not returned by the remote repository\n' >&2
  exit 1
fi

if [[ "${source_revision}" != "${origin_main}" || "${source_revision}" != "${remote_main}" ]]; then
  printf 'main is not exactly synchronized with local and remote origin/main\n' >&2
  exit 1
fi

current_gate="tag_availability"
if git rev-parse --quiet --verify "refs/tags/${tag}" >/dev/null; then
  printf 'release tag already exists locally: %s\n' "${tag}" >&2
  exit 1
fi

set +e
git ls-remote --exit-code --tags origin "refs/tags/${tag}" "refs/tags/${tag}^{}" \
  >"${report_root}/logs/remote-tag.log" 2>&1
remote_tag_status=$?
set -e

case "${remote_tag_status}" in
  0)
    printf 'release tag already exists on origin: %s\n' "${tag}" >&2
    exit 1
    ;;
  2) ;;
  *)
    printf 'could not prove remote tag availability for %s\n' "${tag}" >&2
    exit 1
    ;;
esac

current_gate="hex_version_availability"
hex_status="$(
  curl --fail-with-body --silent --show-error \
    --output "${scratch_root}/hex-release-response.json" \
    --write-out '%{http_code}' \
    "https://hex.pm/api/packages/simd_json/releases/${version}" || true
)"

case "${hex_status}" in
  404) ;;
  200)
    printf 'Hex release already exists: simd_json %s\n' "${version}" >&2
    exit 1
    ;;
  *)
    printf 'could not prove Hex version availability; HTTP status %s\n' \
      "${hex_status:-unavailable}" >&2
    exit 1
    ;;
esac

export MIX_ENV="${release_mix_env}"
run_step release_tool_bootstrap bash scripts/ci/bootstrap_release_tools.sh

current_gate="version_identity"
mix_version="$(
  mix run --no-start -e 'IO.write(Mix.Project.config() |> Keyword.fetch!(:version))' |
    tail -n 1
)"
docs_source_ref="$(
  mix run --no-start -e 'IO.write(Mix.Project.config() |> Keyword.fetch!(:docs) |> Keyword.fetch!(:source_ref))' |
    tail -n 1
)"

if [[ "${mix_version}" != "${version}" ]]; then
  printf 'Mix version %s does not match proposed version %s\n' \
    "${mix_version}" "${version}" >&2
  exit 1
fi

if ! grep -Fqx "## ${version}" CHANGELOG.md; then
  printf 'CHANGELOG.md is missing exact release heading: ## %s\n' "${version}" >&2
  exit 1
fi

if [[ "${docs_source_ref}" != "${tag}" ]]; then
  printf 'ExDoc source ref %s does not match proposed tag %s\n' \
    "${docs_source_ref}" "${tag}" >&2
  exit 1
fi

run_step formatting mix format --check-formatted
run_step strict_documentation mix docs --warnings-as-errors --output "${scratch_root}/docs"

SIMD_JSON_PACKAGE_EVIDENCE_DIR="${report_root}/package" \
  run_step package_inventory bash scripts/ci/verify_package_documentation.sh

run_step qualification_freshness mix simd_json.verify_qualification
run_step spec_validation mix spec.check --no-run-commands --min-strength claimed \
  --base HEAD --output "${scratch_root}/spec-state.json"

qualification_input_sha256="$(
  mix run --no-start -e 'IO.write(SimdJson.Native.BuildGuard.qualification_fingerprint())' |
    tail -n 1
)"
package_sha256="$(cut -d ' ' -f 1 "${report_root}/package/package.sha256")"

current_gate="source_cleanliness"
if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  printf 'release preflight modified source-controlled repository state\n' >&2
  exit 1
fi

preflight_status="passed"
current_gate="complete"
printf 'Release preflight passed: simd_json %s (%s)\n' "${version}" "${source_revision}"
printf 'Evidence: %s\n' "${report_root}"
