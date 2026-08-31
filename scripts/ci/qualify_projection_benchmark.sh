#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.projection_execution.end_to_end_benchmark simd_json.projection_execution.sparse_allocation_advantage simd_json.projection_execution.jason_sparse_benchmark

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/benchmark}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

printf '%s\n' \
  'MIX_ENV=test mix run scripts/benchmarks/run_sparse_projection.exs' \
  >"${evidence_root}/benchmark.command"

env MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  mix run scripts/benchmarks/run_sparse_projection.exs \
  2>&1 | tee "${evidence_root}/benchmark.log"

for evidence in projection-benchmark.json projection-benchmark.md; do
  if [[ ! -s "${evidence_root}/${evidence}" ]]; then
    printf 'projection benchmark did not create %s\n' "${evidence}" >&2
    exit 1
  fi
done

printf 'Milestone 2 sparse projection benchmark passed\n' \
  | tee "${evidence_root}/summary.txt"
