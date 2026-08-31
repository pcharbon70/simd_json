defmodule SimdJson.Native.ReleaseSymbolTest do
  use ExUnit.Case, async: false

  # covers: simd_json.native_build_and_abi.release_symbol_surface simd_json.native_build_and_abi.symbol_visibility
  @tag timeout: 180_000
  test "release ABI and NIF symbols match their checked-in allowlists" do
    {output, status} =
      System.cmd("bash", ["scripts/native/verify_release_symbols.sh"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "release symbol surfaces match their allowlists"
  end
end
