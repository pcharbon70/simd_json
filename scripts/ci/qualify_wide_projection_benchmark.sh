#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.projection_execution.end_to_end_benchmark simd_json.projection_execution.wide_projection_scaling

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/wide-projection}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  mix run scripts/benchmarks/run_wide_projection.exs \
  2>&1 | tee "${evidence_root}/benchmark.log"

test -s "${evidence_root}/wide-projection.json"
test -s "${evidence_root}/wide-projection.md"
grep -Fq '# Million-row wide projection benchmark' "${evidence_root}/wide-projection.md"

printf 'Million-row wide projection benchmark passed\n' | tee "${evidence_root}/summary.txt"
