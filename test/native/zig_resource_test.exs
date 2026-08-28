defmodule SimdJson.Native.ZigResourceTest do
  use ExUnit.Case, async: false

  @tag timeout: 120_000
  # covers: simd_json.document_resource.opaque_handle simd_json.document_resource.complete_ownership
  test "Zig resource state and C status adapter pass their native tests" do
    {output, status} =
      System.cmd("bash", ["scripts/native/run_zig_resource_tests.sh"], stderr_to_stdout: true)

    assert status == 0, output
  end
end
