defmodule Mix.Tasks.SimdJson.VerifyQualification do
  @moduledoc """
  Fails when ABI-relevant inputs no longer match Milestone 1 qualification.
  """

  use Mix.Task

  alias SimdJson.Native.BuildGuard

  @shortdoc "Verifies the Milestone 1 native qualification fingerprint"

  @impl Mix.Task
  # covers: simd_json.native_build_and_abi.dependency_upgrade_gate simd_json.native_build_and_abi.target_qualification
  def run(_arguments) do
    BuildGuard.validate_qualification!()
    Mix.shell().info("Milestone 1 native qualification inputs are current")
  end
end
