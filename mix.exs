defmodule SimdJson.MixProject do
  # covers: simd_json.package.mix_library simd_json.package.specled_tooling simd_json.package.native_build_tooling simd_json.package.native_source_distribution simd_json.native_build_and_abi.pinned_toolchain simd_json.release.public_identity simd_json.release.project_license simd_json.release.consumer_documentation simd_json.release.precompiled_delivery
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/simd_json"

  @user_guides [
    "docs/guides/getting-started.md",
    "docs/guides/decoding-json.md",
    "docs/guides/selecting-fields.md",
    "docs/guides/streaming-large-files.md",
    "docs/guides/deployment.md",
    "docs/guides/errors-limits-performance.md"
  ]

  @benchmark_guides [
    "docs/benchmarks/README.md",
    "docs/benchmarks/reports/sparse-projection/projection-benchmark.md",
    "docs/benchmarks/reports/stream-etl/stream-etl.md",
    "docs/benchmarks/reports/eager-decode/decode-benchmark.md",
    "docs/benchmarks/reports/wide-projection/wide-projection.md"
  ]

  @benchmark_extras [
    {"docs/benchmarks/README.md", filename: "benchmarks", title: "Benchmark Reports"},
    {"docs/benchmarks/reports/sparse-projection/projection-benchmark.md",
     filename: "benchmark-sparse-projection", title: "Sparse Projection Benchmark"},
    {"docs/benchmarks/reports/stream-etl/stream-etl.md",
     filename: "benchmark-stream-etl", title: "Stream ETL Benchmark"},
    {"docs/benchmarks/reports/eager-decode/decode-benchmark.md",
     filename: "benchmark-eager-decode", title: "Eager Decode Benchmark"},
    {"docs/benchmarks/reports/wide-projection/wide-projection.md",
     filename: "benchmark-wide-projection", title: "Wide Projection Benchmark"}
  ]

  def project do
    [
      app: :simd_json,
      name: "SimdJson",
      version: @version,
      elixir: "~> 1.18.4",
      start_permanent: Mix.env() == :prod,
      description: "File-backed SIMD JSON projection and bounded streaming for Elixir",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {SimdJson.Application, []},
      extra_applications: [:crypto, :inets, :logger, :public_key, :ssl]
    ]
  end

  defp deps do
    [
      {:zigler, "== 0.16.0", runtime: false, optional: true},
      {:telemetry, "~> 1.3"},
      {:jason, "== 1.4.5", only: [:dev, :test], runtime: false},
      {:spec_led_ex,
       github: "specleddev/specled_ex",
       ref: "f0d20dba6786a8f1dff0d7365a113b23db696fc1",
       only: [:dev, :test],
       runtime: false}
    ]
  end

  defp package do
    # The native directory deliberately includes the upstream source, its
    # provenance manifest, and both upstream license files in Hex artifacts.
    [
      name: "simd_json",
      maintainers: ["Pascal Charbonneau"],
      licenses: ["MIT"],
      links: %{
        "Documentation" => "https://hexdocs.pm/simd_json",
        "GitHub" => @source_url,
        "Homepage" => @source_url,
        "Issues" => "#{@source_url}/issues"
      },
      exclude_patterns: [
        ~r/(?:^|\/)\.Elixir\..*\.zig$/,
        ~r/(?:^|\/)(?:_build|deps|doc|cover|test|bench|scripts)(?:\/|$)/,
        ~r/(?:^|\/)(?:\.git|\.github|\.spec)(?:\/|$)/,
        ~r/(?:^|\/)(?:\.env(?:\..*)?|credentials?|secrets?)(?:\/|$)/i,
        ~r/(?:^|\/).*(?:~|\.swp|\.swo|\.DS_Store)$/
      ],
      files: [
        "lib/simd_json.ex",
        "lib/simd_json",
        "native/manifest.exs",
        "native/qualification/milestone_1.exs",
        "native/precompiled",
        "native/include",
        "native/src",
        "native/symbols",
        "native/vendor",
        "native/zig",
        "docs/guides",
        "docs/benchmarks",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "CHANGELOG.md",
        "SECURITY.md",
        "CONTRIBUTING.md",
        ".tool-versions",
        "mix.exs",
        "mix.lock",
        "README.md"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras:
        [
          {"README.md", filename: "readme", title: "Overview"},
          {"CHANGELOG.md", filename: "changelog", title: "Changelog"},
          {"SECURITY.md", filename: "security", title: "Security"},
          {"CONTRIBUTING.md", filename: "contributing", title: "Contributing"},
          {"LICENSE", filename: "license", title: "License"},
          {"THIRD_PARTY_NOTICES.md",
           filename: "third-party-notices", title: "Third-Party Notices"}
        ] ++ @user_guides ++ @benchmark_extras,
      groups_for_extras: [
        "User guides": @user_guides,
        "Release notes": ["CHANGELOG.md"],
        Security: ["SECURITY.md"],
        Contributing: ["CONTRIBUTING.md"],
        Benchmarks: @benchmark_guides
      ]
    ]
  end
end
