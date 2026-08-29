defmodule SimdJson.Native.CAbiConformanceTest do
  use ExUnit.Case, async: false

  # covers: simd_json.native_build_and_abi.c_abi_conformance simd_json.native_build_and_abi.cpp_exception_translation simd_json.native_build_and_abi.exception_containment simd_json.native_build_and_abi.partial_failure_cleanup simd_json.projection_engine.prefix_sharing_plan simd_json.projection_engine.private_abi_v2 simd_json.projection_engine.exception_and_failure_cleanup simd_json.projection_engine.abi_v2_conformance
  test "the independent C caller passes the ordinary ABI matrix" do
    {output, status} =
      System.cmd("bash", ["scripts/native/run_c_abi_conformance.sh", "ordinary"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "C ABI conformance passed"
    assert output =~ "projection plan conformance passed abi=2"
  end
end
