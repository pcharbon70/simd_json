#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.native_execution.large_parse_responsiveness simd_json.native_execution.caller_dies_while_running simd_json.native_execution.threaded_submission_failure simd_json.native_execution.large_gc_teardown simd_json.native_execution.reload_cleanup simd_json.document_resource.repeated_close simd_json.document_resource.gc_cleanup simd_json.document_resource.native_memory_baseline

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/runtime}"
seed="${SIMD_JSON_LIFECYCLE_SEED:-260829001}"

mkdir -p "${evidence_root}"

run_step() {
  local name="$1"
  shift

  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

{
  printf 'source_revision=%s\n' "$(git -C "${repository_root}" rev-parse HEAD)"
  printf 'source_tree=%s\n' "$(git -C "${repository_root}" rev-parse HEAD^{tree})"
  printf 'lifecycle_seed=%s\n' "${seed}"
  printf 'ci=%s\n' "${CI:-false}"
  printf 'github_actions=%s\n' "${GITHUB_ACTIONS:-false}"
} >"${evidence_root}/environment.txt"

run_step scheduler \
  env MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  mix test test/qualification/scheduler_qualification_test.exs --seed 0

run_step lifecycle \
  env MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  SIMD_JSON_LIFECYCLE_SEED="${seed}" \
  mix test test/qualification/lifecycle_memory_qualification_test.exs --seed 0

run_step deterministic_runtime_corpus \
  env MIX_ENV=test mix test \
  test/native/threaded_document_open_test.exs \
  test/native/threaded_teardown_test.exs \
  test/native/native_execution_integration_test.exs \
  test/simd_json/phase_5_integration_test.exs --seed 0

printf 'Milestone 1 runtime qualification passed\n' | tee "${evidence_root}/summary.txt"
