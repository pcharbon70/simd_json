#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.document_resource.opaque_handle simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.complete_ownership simd_json.document_resource.single_owner simd_json.document_resource.lifecycle simd_json.document_resource.idempotent_close simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention simd_json.document_resource.deferred_large_cleanup simd_json.document_resource.test_accounting simd_json.document_resource.input_lifetime simd_json.document_resource.repeated_close simd_json.document_resource.non_owner_rejection simd_json.document_resource.partial_open_failure simd_json.document_resource.gc_cleanup simd_json.document_resource.native_memory_baseline

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/document-resource}"

mkdir -p "${evidence_root}"

run_step() {
  local name="$1"
  shift

  printf '%s\n' "$*" >"${evidence_root}/${name}.command"
  "$@" 2>&1 | tee "${evidence_root}/${name}.log"
}

run_step zig_ordinary bash scripts/native/run_zig_resource_tests.sh ordinary
run_step zig_sanitizer bash scripts/native/run_zig_resource_tests.sh sanitizer

run_step resource_corpus \
  env MIX_ENV=test SIMD_JSON_QUALIFICATION_DIR="${evidence_root}" \
  SIMD_JSON_LIFECYCLE_SEED=260829001 \
  mix test \
  test/native/document_resource_registration_test.exs \
  test/native/zig_resource_test.exs \
  test/native/document_resource_policy_test.exs \
  test/native/threaded_document_open_test.exs \
  test/native/threaded_teardown_test.exs \
  test/simd_json/document_api_test.exs \
  test/simd_json/phase_5_integration_test.exs \
  test/qualification/lifecycle_memory_qualification_test.exs --seed 0

printf 'Milestone 1 document-resource qualification passed\n' | tee "${evidence_root}/summary.txt"
