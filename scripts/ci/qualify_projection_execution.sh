#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.projection_execution.threaded_projection simd_json.projection_execution.one_correlated_operation simd_json.projection_execution.owner_first_admission simd_json.projection_execution.exclusive_document_selection simd_json.projection_execution.committed_consumption simd_json.projection_execution.preadmission_nonconsumption simd_json.projection_execution.generation_and_resource_retention simd_json.projection_execution.binary_temporary_document simd_json.projection_execution.close_interlock simd_json.projection_execution.cancellation_boundaries simd_json.projection_execution.native_memory_baseline simd_json.projection_execution.scheduler_qualification simd_json.projection_execution.end_to_end_benchmark simd_json.projection_execution.sparse_allocation_advantage simd_json.projection_execution.preproduction_boundary simd_json.projection_execution.binary_operation_lifetime simd_json.projection_execution.document_one_shot simd_json.projection_execution.non_owner_and_close_race simd_json.projection_execution.submission_rejection_retry simd_json.projection_execution.caller_death_and_cancellation simd_json.projection_execution.large_projection_responsiveness simd_json.projection_execution.jason_sparse_benchmark

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/projection-execution}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}/runtime" \
  bash scripts/ci/qualify_projection_runtime.sh 2>&1 \
  | tee "${evidence_root}/runtime.log"

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}/benchmark" \
  bash scripts/ci/qualify_projection_benchmark.sh 2>&1 \
  | tee "${evidence_root}/benchmark.log"

printf 'Milestone 2 projection execution qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
