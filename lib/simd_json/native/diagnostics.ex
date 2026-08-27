defmodule SimdJson.Native.Diagnostics do
  @moduledoc false

  alias SimdJson.Native.BuildGuard
  alias SimdJson.Native.BuildSmoke

  @doc false
  # covers: simd_json.native_build_and_abi.clean_checkout_build simd_json.native_build_and_abi.target_qualification
  def build do
    %{
      target: BuildSmoke.target_triple(),
      runtime_implementation: BuildSmoke.runtime_implementation(),
      simdjson_version: BuildSmoke.simdjson_version(),
      simdjson_padding: BuildSmoke.simdjson_padding(),
      native_fingerprint: BuildGuard.fingerprint()
    }
  end
end
