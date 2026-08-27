defmodule SimdJson.Native.BuildSmokeTest do
  use ExUnit.Case, async: true

  alias SimdJson.Native.Diagnostics

  @manifest Code.eval_file("native/manifest.exs") |> elem(0)
  @simdjson Keyword.fetch!(@manifest, :simdjson)
  @primary_target Keyword.fetch!(@manifest, :primary_target)

  # covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.target_qualification simd_json.native_build_and_abi.clean_supported_build
  test "loads the vendored smoke NIF and reports qualified runtime data" do
    diagnostic = Diagnostics.build()

    assert diagnostic.target == Keyword.fetch!(@primary_target, :triple)

    assert diagnostic.runtime_implementation in Keyword.fetch!(
             @primary_target,
             :expected_simdjson_implementations
           )

    assert diagnostic.simdjson_version == 4_006_009
    assert diagnostic.simdjson_padding == Keyword.fetch!(@simdjson, :padding_bytes)
    assert diagnostic.native_fingerprint =~ ~r/^[0-9a-f]{64}$/
  end

  test "does not add build diagnostics to the public SimdJson API" do
    refute {:build_diagnostics, 0} in SimdJson.__info__(:functions)
    refute {:runtime_implementation, 0} in SimdJson.__info__(:functions)
  end
end
