#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
report_root="${SIMD_JSON_BENCHMARK_REPORT_DIR:-${repository_root}/docs/benchmarks/reports}"

run_benchmark() {
  local name="$1"
  local script="$2"
  local destination="${report_root}/${name}"

  mkdir -p "${destination}"
  printf '\n==> Running %s benchmark\n' "${name}"
  env MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${destination}" \
    mix run "${script}"
}

cd "${repository_root}"

run_benchmark sparse-projection scripts/benchmarks/run_sparse_projection.exs
run_benchmark stream-etl scripts/benchmarks/run_stream_etl.exs
run_benchmark eager-decode scripts/benchmarks/run_decode.exs
run_benchmark wide-projection scripts/benchmarks/run_wide_projection.exs

expected_reports=(
  sparse-projection/projection-benchmark.json
  sparse-projection/projection-benchmark.md
  stream-etl/stream-etl.json
  stream-etl/stream-etl.md
  eager-decode/decode-benchmark.json
  eager-decode/decode-benchmark.md
  wide-projection/wide-projection.json
  wide-projection/wide-projection.md
)

for report in "${expected_reports[@]}"; do
  test -s "${report_root}/${report}"
done

printf '\nAll benchmark reports written to %s\n' "${report_root}"
