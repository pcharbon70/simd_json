#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/decode}"
seed="${SIMD_JSON_QUALIFICATION_SEED:-56061}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

run_step() {
  local name="$1"
  shift
  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

decode_tests=(
  test/simd_json/decode_options_test.exs
  test/simd_json/decode_api_test.exs
  test/native/decode_materialization_test.exs
  test/native/decode_pool_lifecycle_test.exs
  test/native/pool_telemetry_test.exs
  test/qualification/decode_compatibility_qualification_test.exs
  test/qualification/decode_scheduler_qualification_test.exs
)

for offset in 0 1 2; do
  run_step "decode_runtime_${offset}" env MIX_ENV=test \
    SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
    mix test "${decode_tests[@]}" --seed "$((seed + offset))"
done

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  run_step benchmark bash scripts/ci/qualify_decode_benchmark.sh

test -s "${evidence_root}/decode-benchmark.json"
test -s "${evidence_root}/decode-scheduler.json"
printf 'Milestone 5 decode compatibility and runtime qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
