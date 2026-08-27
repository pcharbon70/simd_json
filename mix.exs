defmodule SimdJson.MixProject do
  # covers: simd_json.package.mix_library simd_json.package.specled_tooling simd_json.package.native_build_tooling simd_json.native_build_and_abi.pinned_toolchain
  use Mix.Project

  def project do
    [
      app: :simd_json,
      version: "0.1.0",
      elixir: "~> 1.18.4",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zigler, "== 0.16.0", runtime: false},
      {:spec_led_ex,
       github: "specleddev/specled_ex",
       ref: "f0d20dba6786a8f1dff0d7365a113b23db696fc1",
       only: [:dev, :test],
       runtime: false}
    ]
  end
end
