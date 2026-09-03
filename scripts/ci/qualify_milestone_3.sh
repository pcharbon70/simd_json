#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
spec_base="${SIMD_JSON_SPEC_BASE:-origin/main}"
qualification_root="${repository_root}/_build/qualification"
evidence_root="${qualification_root}/acceptance"

cd "${repository_root}"

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  printf 'Milestone 3 qualification requires a clean committed worktree\n' >&2
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

{
  printf 'source_revision=%s\n' "$(git rev-parse HEAD)"
  printf 'source_tree=%s\n' "$(git rev-parse HEAD^{tree})"
  printf 'spec_base=%s\n' "${spec_base}"
  printf 'qualification_input_sha256=%s\n' "$(mix run --no-start -e 'IO.write(SimdJson.Native.BuildGuard.qualification_fingerprint())')"
  printf 'target=%s-%s\n' "$(uname -m)" "$(uname -s)"
  printf 'kernel=%s\n' "$(uname -srvo)"
  printf 'mix=%s\n' "$(mix --version | tr '\n' ' ')"
  printf 'jason=%s\n' "$(mix run --no-start -e 'IO.write(Application.spec(:jason, :vsn))')"
} >"${evidence_root}/environment.txt"

SIMD_JSON_QUALIFICATION_DIR="${qualification_root}/native" \
  run_step native_release bash scripts/ci/qualify_native_release.sh
SIMD_JSON_QUALIFICATION_DIR="${qualification_root}/stream-execution" \
  run_step stream_execution bash scripts/ci/qualify_stream_execution.sh
run_step formatter_plugin mix deps.compile zigler --force
run_step formatting mix format --check-formatted
run_step documentation mix docs --warnings-as-errors
run_step full_test_suite env MIX_ENV=test mix test --seed 0
run_step spec_index mix spec.index
run_step spec_validate mix spec.validate --debug --min-strength claimed
run_step spec_status mix spec.status --no-run-commands --min-strength claimed
run_step spec_next mix spec.next --base "${spec_base}"
run_step spec_check env -u SIMD_JSON_QUALIFICATION_DIR mix spec.check --base "${spec_base}"
run_step traceability env -u SIMD_JSON_QUALIFICATION_DIR mix simd_json.verify_traceability
run_step canonical_state git diff --exit-code -- .spec/state.json

cp .spec/state.json "${evidence_root}/spec-state.json"

for evidence in \
  "${qualification_root}/native/summary.txt" \
  "${qualification_root}/stream-execution/runtime/stream-scheduler.json" \
  "${qualification_root}/stream-execution/runtime/stream-demand.json" \
  "${qualification_root}/stream-execution/runtime/lifecycle.json" \
  "${qualification_root}/stream-execution/benchmark/stream-etl.json"; do
  test -s "${evidence}"
done

if rg -n --fixed-strings -- '- [ ]' .spec/planning/milestone_03_batched_array_streaming/phase-*.md; then
  printf 'Milestone 3 plan retains unchecked work\n' >&2
  exit 1
fi

if rg -n 'milestone_03_bootstrap|status: planned' \
  .spec/specs/streaming_api.spec.md \
  .spec/specs/stream_cursor.spec.md \
  .spec/specs/stream_execution.spec.md; then
  printf 'Milestone 3 retains a bootstrap exception or planned subject\n' >&2
  exit 1
fi

{
  printf 'Milestone 3 acceptance qualification passed\n'
  printf 'source_revision=%s\n' "$(git rev-parse HEAD)"
  printf 'source_tree=%s\n' "$(git rev-parse HEAD^{tree})"
  printf 'specled_findings=0\n'
  printf 'specled_warnings=0\n'
  printf 'stream_etl_threshold=pass\n'
  printf 'preproduction_runtime=true\n'
} | tee "${evidence_root}/summary.txt"

(
  cd "${qualification_root}"
  find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >SHA256SUMS
)
