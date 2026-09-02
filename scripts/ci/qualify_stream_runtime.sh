#!/usr/bin/env bash
set -euo pipefail

# Reproducible Milestone 3 scheduler, local-demand, lifecycle, cancellation,
# and native-memory qualification. Evidence is revision-bound JSON.

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/stream-runtime}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

{
  printf 'source_revision=%s\n' "$(git rev-parse HEAD)"
  printf 'source_tree=%s\n' "$(git rev-parse HEAD^{tree})"
  printf 'target=%s-%s\n' "$(uname -m)" "$(uname -s)"
  printf 'kernel=%s\n' "$(uname -srvo)"
  printf 'mix=%s\n' "$(mix --version | tr '\n' ' ')"
  printf 'heartbeat_period_ms=2\n'
  printf 'p95_budget_us=50000\n'
  printf 'p99_budget_us=250000\n'
  printf 'maximum_budget_us=500000\n'
  printf 'scope=per-stream demand; Milestone 4 global admission is deferred\n'
  printf 'shared_object_reload=unsupported; application restart is qualified\n'
} >"${evidence_root}/environment.txt"

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  MIX_ENV=test mix test --seed 260831006 \
    test/qualification/stream_runtime_qualification_test.exs \
    test/qualification/scheduler_qualification_test.exs \
    test/qualification/lifecycle_memory_qualification_test.exs \
    test/simd_json/phase_5_integration_test.exs \
  2>&1 | tee "${evidence_root}/qualification.log"

for evidence in scheduler.json lifecycle.json stream-scheduler.json stream-demand.json; do
  test -s "${evidence_root}/${evidence}"
done

printf 'Milestone 3 stream runtime qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
