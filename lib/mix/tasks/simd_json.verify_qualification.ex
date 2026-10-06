defmodule Mix.Tasks.SimdJson.VerifyQualification do
  @moduledoc """
  Fails when ABI-relevant inputs no longer match the native qualification
  record.
  """

  use Mix.Task

  alias SimdJson.Native.BuildGuard

  @shortdoc "Verifies the native qualification fingerprint"

  @impl Mix.Task
  # covers: simd_json.native_build_and_abi.dependency_upgrade_gate simd_json.native_build_and_abi.target_qualification
  def run(_arguments) do
    BuildGuard.validate_qualification!()
    Mix.shell().info("Native qualification inputs are current")
  end
end
