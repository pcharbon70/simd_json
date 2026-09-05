#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
spec_base="${SIMD_JSON_SPEC_BASE:-origin/main}"
qualification_root="${repository_root}/_build/qualification"
evidence_root="${qualification_root}/acceptance"
release_mix_env="${SIMD_JSON_RELEASE_MIX_ENV:-test}"
active_mix_env="${MIX_ENV:-${release_mix_env}}"

cd "${repository_root}"

if [[ "${active_mix_env}" != "${release_mix_env}" ]]; then
  printf 'Milestone 5 qualification requires MIX_ENV=%s; received MIX_ENV=%s\n' \
    "${release_mix_env}" "${active_mix_env}" >&2
  exit 1
fi
export MIX_ENV="${release_mix_env}"

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  printf 'Milestone 5 qualification requires a clean committed worktree\n' >&2
  git status --short >&2
  exit 1
fi

case "${qualification_root}" in
  "${repository_root}/_build/qualification") ;;
  *) printf 'refusing unexpected qualification directory\n' >&2; exit 1 ;;
esac

rm -rf -- "${qualification_root}"
mkdir -p "${evidence_root}"

run_step() {
  local name="$1"
  shift
  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

source_revision="$(git rev-parse HEAD)"
source_tree="$(git rev-parse HEAD^{tree})"

{
  printf 'source_revision=%s\n' "${source_revision}"
  printf 'source_tree=%s\n' "${source_tree}"
  printf 'spec_base=%s\n' "${spec_base}"
  printf 'qualification_input_sha256=%s\n' "$(mix run --no-start -e 'IO.write(SimdJson.Native.BuildGuard.qualification_fingerprint())')"
  printf 'target=%s-%s\n' "$(uname -m)" "$(uname -s)"
  printf 'kernel=%s\n' "$(uname -srvo)"
  printf 'mix=%s\n' "$(mix --version | tr '\n' ' ')"
  printf 'jason=%s\n' "$(mix run --no-start -e 'IO.write(Application.spec(:jason, :vsn))')"
} >"${evidence_root}/environment.txt"

SIMD_JSON_QUALIFICATION_DIR="${qualification_root}/native" \
  run_step native_release bash scripts/ci/qualify_native_release.sh
SIMD_JSON_QUALIFICATION_DIR="${qualification_root}/native-pool" \
  run_step native_pool bash scripts/ci/qualify_native_pool.sh
SIMD_JSON_QUALIFICATION_DIR="${qualification_root}/decode" \
  run_step decode bash scripts/ci/qualify_decode.sh

run_step release_tool_bootstrap bash scripts/ci/bootstrap_release_tools.sh
run_step formatting mix format --check-formatted
run_step documentation mix docs --warnings-as-errors
run_step full_test_suite env MIX_ENV=test mix test --seed 0
run_step spec_index mix spec.index
run_step spec_validate mix spec.validate --debug --min-strength claimed
run_step spec_status mix spec.status --no-run-commands --min-strength claimed
run_step spec_check mix spec.check --no-run-commands --min-strength claimed --base "${spec_base}"
run_step restore_canonical_state git restore --source=HEAD -- .spec/state.json
run_step traceability mix simd_json.verify_traceability
run_step canonical_state git diff --exit-code -- .spec/state.json

cp .spec/state.json "${evidence_root}/spec-state.json"

for evidence in \
  "${qualification_root}/native/summary.txt" \
  "${qualification_root}/native-pool/summary.txt" \
  "${qualification_root}/decode/decode-benchmark.json" \
  "${qualification_root}/decode/decode-scheduler.json" \
  "${qualification_root}/decode/summary.txt"; do
  test -s "${evidence}"
done

if rg -n --fixed-strings -- '- [ ]' .spec/planning/milestone_05_compatible_decode/phase-*.md; then
  printf 'Milestone 5 plan retains unchecked work\n' >&2
  exit 1
fi

if rg -n 'bootstrap:|status: planned' .spec/specs/decode_api.spec.md; then
  printf 'Milestone 5 decode subject is not active\n' >&2
  exit 1
fi

{
  printf 'Milestone 5 acceptance qualification passed\n'
  printf 'source_revision=%s\n' "${source_revision}"
  printf 'source_tree=%s\n' "${source_tree}"
  printf 'specled_findings=0\n'
  printf 'specled_warnings=0\n'
  printf 'decode_compatibility=pass\n'
  printf 'decode_scheduler=pass\n'
  printf 'decode_benchmark=pass\n'
} | tee "${evidence_root}/summary.txt"

(
  cd "${qualification_root}"
  find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >SHA256SUMS
)
