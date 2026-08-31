#!/usr/bin/env bash
set -euo pipefail

# covers: simd_json.document_api.open_contract simd_json.document_api.binary_only simd_json.document_api.close_contract simd_json.document_api.document_argument_validation simd_json.document_api.opaque_document_type simd_json.document_api.structured_error simd_json.document_api.initial_error_reasons simd_json.document_api.logical_offsets simd_json.document_api.error_redaction simd_json.document_api.valid_json_values simd_json.document_api.milestone_scope simd_json.document_api.open_and_close simd_json.document_api.all_top_level_values simd_json.document_api.invalid_input_errors simd_json.document_api.non_binary_argument simd_json.document_api.invalid_document_argument simd_json.document_api.redacted_failure simd_json.document_api.close_and_non_owner simd_json.document_api.no_future_surface simd_json.projection_api.select_contract simd_json.projection_api.source_argument_validation simd_json.projection_api.projection_grammar simd_json.projection_api.complete_preflight_validation simd_json.projection_api.output_key_identity simd_json.projection_api.scalar_results simd_json.projection_api.fresh_string_results simd_json.projection_api.atomic_result simd_json.projection_api.projection_error_reasons simd_json.projection_api.error_path simd_json.projection_api.milestone_scope simd_json.projection_api.binary_multi_select simd_json.projection_api.document_select simd_json.projection_api.invalid_source_argument simd_json.projection_api.invalid_projection simd_json.projection_api.all_scalar_types simd_json.projection_api.path_failures simd_json.projection_api.atom_and_surface_safety

repository_root="$(git rev-parse --show-toplevel)"
evidence_root="${SIMD_JSON_QUALIFICATION_DIR:-${repository_root}/_build/qualification/document-api}"

mkdir -p "${evidence_root}"

env MIX_ENV=test mix test \
  test/simd_json_test.exs \
  test/simd_json/document_api_test.exs \
  test/simd_json/error_test.exs \
  test/simd_json/public_surface_test.exs \
  test/simd_json/phase_5_integration_test.exs \
  test/simd_json/projection_validation_test.exs \
  test/simd_json/select_test.exs \
  test/benchmark/sparse_fixture_test.exs \
  test/qualification/lifecycle_memory_qualification_test.exs --seed 0 2>&1 \
  | tee "${evidence_root}/public-api.log"

SIMD_JSON_QUALIFICATION_DIR="${evidence_root}/scope" \
  bash scripts/ci/verify_milestone_1_scope.sh 2>&1 \
  | tee "${evidence_root}/scope.log"

printf 'Milestone 1 document and Milestone 2 projection API qualification passed\n' \
  | tee "${evidence_root}/summary.txt"
