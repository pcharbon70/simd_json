#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/native-pool}"
seed="${SIMD_JSON_QUALIFICATION_SEED:-46031}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

run_step() {
  local name="$1"
  shift
  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

pool_tests=(
  test/native/pool_saturation_test.exs
  test/native/pool_cancellation_test.exs
  test/native/pool_delivery_test.exs
  test/native/pool_resource_serialization_test.exs
  test/native/pool_worker_lifecycle_test.exs
)

# Fixed adjacent seeds make cancellation, delivery, close, and shutdown races
# reproducible while varying ExUnit process order.
for offset in 0 1 2; do
  run_step "pool_races_${offset}" env MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
    mix test "${pool_tests[@]}" --seed "$((seed + offset))"
done

run_step c_abi_sanitizer env SIMD_JSON_QUALIFICATION_SEED="${seed}" \
  bash scripts/native/run_c_abi_conformance.sh sanitizer
run_step zig_resource_sanitizer bash scripts/native/run_zig_resource_tests.sh sanitizer
run_step nif_sanitizer bash scripts/native/run_nif_sanitizer_tests.sh
run_step release_symbols bash scripts/native/verify_release_symbols.sh

test -s "${evidence_root}/saturation.json"
printf 'Milestone 4 native-pool race and sanitizer qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
