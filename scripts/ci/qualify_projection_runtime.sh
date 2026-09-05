#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.generation_and_resource_retention simd_json.projection_execution.binary_temporary_document simd_json.projection_execution.close_interlock simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.native_memory_baseline simd_json.projection_execution.scheduler_qualification simd_json.projection_execution.preadmission_nonconsumption simd_json.projection_execution.owner_first_admission simd_json.projection_execution.exclusive_document_selection simd_json.projection_execution.committed_consumption simd_json.projection_execution.preproduction_boundary simd_json.projection_execution.binary_operation_lifetime simd_json.projection_execution.document_one_shot simd_json.projection_execution.non_owner_and_close_race simd_json.projection_execution.submission_rejection_retry simd_json.projection_execution.caller_death_and_cancellation simd_json.projection_execution.large_projection_responsiveness

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/projection-runtime}"
seed="${SIMD_JSON_LIFECYCLE_SEED:-260831006}"

cd "${repository_root}"
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
  printf 'target=%s-%s\n' "$(uname -m)" "$(uname -s)"
  printf 'kernel=%s\n' "$(uname -srvo)"
  printf 'mix=%s\n' "$(mix --version | tr '\n' ' ')"
  printf 'normal_schedulers=%s\n' "$(mix run --no-start -e 'IO.write(:erlang.system_info(:schedulers))')"
  printf 'dirty_cpu_schedulers=%s\n' "$(mix run --no-start -e 'IO.write(:erlang.system_info(:dirty_cpu_schedulers))')"
  printf 'dirty_io_schedulers=%s\n' "$(mix run --no-start -e 'IO.write(:erlang.system_info(:dirty_io_schedulers))')"
  printf 'lifecycle_seed=%s\n' "${seed}"
} >"${evidence_root}/environment.txt"

run_step runtime_policy mix test \
  test/native/threaded_projection_operation_test.exs \
  test/native/projection_binary_lifetime_test.exs \
  test/native/projection_document_lifecycle_test.exs \
  test/native/threaded_projection_integration_test.exs \
  --seed 0

run_step scheduler env SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  mix test test/qualification/projection_scheduler_qualification_test.exs --seed 0

run_step million_row env SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  mix test test/qualification/projection_million_row_qualification_test.exs --seed 0

run_step lifecycle env \
  SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  SIMD_JSON_LIFECYCLE_SEED="${seed}" \
  mix test test/qualification/projection_lifecycle_qualification_test.exs --seed 0

for evidence in projection-scheduler.json projection-million-row.json projection-lifecycle.json; do
  if [[ ! -s "${evidence_root}/${evidence}" ]]; then
    printf 'projection qualification did not create %s\n' "${evidence}" >&2
    exit 1
  fi
done

printf 'Milestone 2 projection scheduler and lifecycle qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
