#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/stream-execution}"

cd "${repository_root}"
mkdir -p "${evidence_root}"

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}/runtime" \
  bash scripts/ci/qualify_stream_runtime.sh \
  2>&1 | tee "${evidence_root}/runtime.log"

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}/benchmark" \
  bash scripts/ci/qualify_stream_benchmark.sh \
  2>&1 | tee "${evidence_root}/benchmark.log"

printf 'Milestone 3 stream execution qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
