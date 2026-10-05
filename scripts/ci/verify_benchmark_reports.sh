#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
report_root="${SIMD_JSON_BENCHMARK_REPORT_DIR:-${repository_root}/docs/benchmarks/reports}"
index="${repository_root}/docs/benchmarks/README.md"

report_pairs=(
  sparse-projection/projection-benchmark
  stream-etl/stream-etl
  eager-decode/decode-benchmark
  wide-projection/wide-projection
)

source_revision=""

test -s "${index}"
grep -q 'Whole-VM RSS' "${index}"
grep -q 'Worker-process memory' "${index}"
grep -qi 'file-backed' "${index}"

for report in "${report_pairs[@]}"; do
  markdown="${report_root}/${report}.md"
  json="${report_root}/${report}.json"

  test -s "${markdown}"
  test -s "${json}"
  grep -q '^# ' "${markdown}"
  grep -q '"schema_version":1' "${json}"

  report_revision="$(sed -n 's/^Source revision: `\([0-9a-f]\{40\}\)`.*/\1/p' "${markdown}")"
  test -n "${report_revision}"
  grep -q "\"source_revision\":\"${report_revision}\"" "${json}"

  if [[ -z "${source_revision}" ]]; then
    source_revision="${report_revision}"
  else
    test "${report_revision}" = "${source_revision}"
  fi
done

printf 'Benchmark report set verified at source revision %s\n' "${source_revision}"
