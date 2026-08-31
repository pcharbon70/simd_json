#!/usr/bin/env bash
set -euo pipefail

# Complete Milestone 2 release-candidate gate. SpecLed executes each active
# subject command; this command adds the clean-worktree formatting,
# documentation, full-suite, reconciliation, and immutable evidence envelope.

repository_root="$(git rev-parse --show-toplevel)"
spec_base="${SIMD_JSON_SPEC_BASE:-main}"
qualification_root="${repository_root}/_build/qualification"
evidence_root="${qualification_root}/acceptance"

cd "${repository_root}"

if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  printf 'Milestone 2 qualification requires a clean committed worktree\n' >&2
  git status --short >&2
  exit 1
fi

case "${qualification_root}" in
  "${repository_root}/_build/qualification") ;;
  *)
    printf 'refusing to replace unexpected qualification directory: %s\n' \
      "${qualification_root}" >&2
    exit 1
    ;;
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
  printf 'qualification_input_sha256=%s\n' \
    "$(mix run --no-start -e 'IO.write(SimdJson.Native.BuildGuard.qualification_fingerprint())')"
  printf 'target=%s-%s\n' "$(uname -m)" "$(uname -s)"
  printf 'kernel=%s\n' "$(uname -srvo)"
  printf 'mix=%s\n' "$(mix --version | tr '\n' ' ')"
  printf 'jason=%s\n' \
    "$(mix run --no-start -e 'IO.write(Application.spec(:jason, :vsn) || "unloaded")')"
  printf 'ci=%s\n' "${CI:-false}"
  printf 'github_actions=%s\n' "${GITHUB_ACTIONS:-false}"
} >"${evidence_root}/environment.txt"

run_step formatter_plugin mix deps.compile zigler --force
run_step formatting mix format --check-formatted
run_step documentation mix docs --warnings-as-errors
run_step full_test_suite env MIX_ENV=test mix test --seed 0
run_step spec_index mix spec.index
run_step spec_next mix spec.next --base "${spec_base}"
run_step spec_validate mix spec.validate --debug --min-strength claimed
run_step spec_status mix spec.status --no-run-commands --min-strength claimed
run_step spec_check env -u SIMD_JSON_QUALIFICATION_DIR \
  mix spec.check --base "${spec_base}"
run_step traceability env -u SIMD_JSON_QUALIFICATION_DIR \
  mix simd_json.verify_traceability
run_step canonical_state git diff --exit-code -- .spec/state.json

cp .spec/state.json "${evidence_root}/spec-state.json"

for evidence in \
  "${qualification_root}/projection-execution/runtime/projection-scheduler.json" \
  "${qualification_root}/projection-execution/runtime/projection-lifecycle.json" \
  "${qualification_root}/projection-execution/benchmark/projection-benchmark.json" \
  "${qualification_root}/projection-execution/benchmark/projection-benchmark.md" \
  "${qualification_root}/traceability/inventory.json"; do
  if [[ ! -s "${evidence}" ]]; then
    printf 'Milestone 2 qualification evidence is missing: %s\n' "${evidence}" >&2
    exit 1
  fi
done

unchecked="$(rg -n --fixed-strings -- '- [ ]' \
  .spec/planning/milestone_02_projection_api/phase-*.md || true)"

if [[ -n "${unchecked}" ]]; then
  printf 'Milestone 2 plan retains unchecked work:\n%s\n' "${unchecked}" >&2
  exit 1
fi

executed_claims="$(mix run --no-start -e '
  subjects = ~w(
    simd_json.native_build_and_abi
    simd_json.document_resource
    simd_json.native_execution
    simd_json.document_api
    simd_json.projection_api
    simd_json.projection_engine
    simd_json.projection_execution
  )

  count =
    ".spec/state.json"
    |> File.read!()
    |> :json.decode()
    |> get_in(["verification", "claims"])
    |> Enum.count(&(&1["subject_id"] in subjects and &1["strength"] == "executed"))

  IO.write(count)
')"

{
  printf 'Milestone 2 release-candidate qualification passed\n'
  printf 'source_revision=%s\n' "${source_revision}"
  printf 'source_tree=%s\n' "${source_tree}"
  printf 'specled_findings=0\n'
  printf 'specled_warnings=0\n'
  printf 'milestone_1_and_2_executed_claims=%s\n' "${executed_claims}"
  printf 'projection_allocation_threshold=pass\n'
  printf 'preproduction_runtime=true\n'
} | tee "${evidence_root}/summary.txt"

(
  cd "${qualification_root}"
  find . -type f ! -name SHA256SUMS -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 sha256sum >SHA256SUMS
)
