#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/stream-etl}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  mix run scripts/benchmarks/run_stream_etl.exs \
  2>&1 | tee "${evidence_root}/benchmark.log"

test -s "${evidence_root}/stream-etl.json"
test -s "${evidence_root}/stream-etl.md"

for required_text in \
  '# Stream ETL benchmark: SimdJson vs Jason' \
  '## Side-by-side measurements' \
  'Worker process peak (MiB)' \
  'Whole-VM RSS peak (MiB)' \
  '## Measurement definitions'; do
  grep -Fq "${required_text}" "${evidence_root}/stream-etl.md"
done

printf 'Milestone 3 stream ETL benchmark passed\n' | tee "${evidence_root}/summary.txt"
