defmodule SimdJson.Native.ZigResourceTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  # covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership simd_json.document_resource.padded_owned_copy simd_json.document_resource.zero_copy_disabled simd_json.document_resource.lifecycle simd_json.document_resource.reverse_destruction simd_json.document_resource.parent_retention simd_json.document_resource.test_accounting simd_json.document_resource.input_lifetime simd_json.document_resource.partial_open_failure
  test "Zig resource state and C status adapter pass their native tests" do
    {output, status} =
      System.cmd("bash", ["scripts/native/run_zig_resource_tests.sh"], stderr_to_stdout: true)

    assert status == 0, output
  end
end
