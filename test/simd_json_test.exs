defmodule SimdJsonTest do
  use ExUnit.Case, async: false

  # covers: simd_json.document_api.open_contract simd_json.document_api.binary_only simd_json.document_api.close_contract simd_json.document_api.opaque_document_type simd_json.document_api.structured_error simd_json.document_api.error_redaction simd_json.document_api.non_binary_argument simd_json.document_api.redacted_failure simd_json.document_api.close_and_non_owner simd_json.projection_api.select_contract simd_json.projection_api.fresh_string_results simd_json.projection_api.projection_error_reasons simd_json.projection_api.error_path simd_json.projection_api.milestone_scope simd_json.projection_execution.document_one_shot
  doctest SimdJson
  doctest SimdJson.Document
  doctest SimdJson.Error

  test "defines the library's root module" do
    assert Code.ensure_loaded?(SimdJson)
  end
end
