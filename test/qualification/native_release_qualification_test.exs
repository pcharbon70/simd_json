defmodule SimdJson.Native.ReleaseQualificationTest do
  use ExUnit.Case, async: false

  alias SimdJson.Native.BuildGuard
  alias SimdJson.Native.Diagnostics

  @qualification Code.eval_file("native/qualification/milestone_1.exs") |> elem(0)
  @manifest Code.eval_file("native/manifest.exs") |> elem(0)

  # covers: simd_json.native_build_and_abi.clean_supported_build simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.dependency_upgrade_gate
  test "supported runtime matches the current qualification record" do
    assert :ok = BuildGuard.validate_qualification!()

    diagnostic = Diagnostics.build()
    primary = Keyword.fetch!(@manifest, :primary_target)
    supported = Keyword.fetch!(@qualification, :supported_targets)

    assert diagnostic.target == Keyword.fetch!(primary, :triple)

    assert diagnostic.runtime_implementation in Keyword.fetch!(
             primary,
             :expected_simdjson_implementations
           )

    assert Enum.any?(supported, fn target ->
             Keyword.fetch!(target, :triple) == diagnostic.target
           end)
  end

  # covers: simd_json.native_build_and_abi.unsupported_target_rejection simd_json.native_build_and_abi.clean_supported_build
  test "qualification remains fail-closed outside the single supported target" do
    for target <- [
          "aarch64-linux-gnu",
          "x86_64-macos",
          "aarch64-macos",
          "x86_64-linux-musl",
          "x86_64-windows-msvc"
        ] do
      assert_raise SimdJson.Native.BuildError, ~r/unsupported native target/, fn ->
        BuildGuard.validate!(target: target)
      end

      assert_raise SimdJson.Native.BuildError, ~r/qualification evidence is unavailable/, fn ->
        BuildGuard.validate_qualification!(target: target)
      end
    end
  end
end
