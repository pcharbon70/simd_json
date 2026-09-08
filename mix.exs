defmodule SimdJson.MixProject do
  # covers: simd_json.package.mix_library simd_json.package.specled_tooling simd_json.package.native_build_tooling simd_json.package.native_source_distribution simd_json.native_build_and_abi.pinned_toolchain simd_json.release.public_identity simd_json.release.project_license simd_json.release.consumer_documentation
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/pcharbon70/simd_json"

  @milestone_guides [
    "docs/milestones/README.md",
    "docs/milestones/01-native-foundation.md",
    "docs/milestones/02-projection-api.md",
    "docs/milestones/03-batched-array-streaming.md",
    "docs/milestones/04-worker-pool-and-operations.md",
    "docs/milestones/05-compatible-decode-api.md"
  ]

  @operations_guides [
    "docs/milestones/01-native-foundation-operations.md",
    "docs/milestones/02-projection-api-operations.md",
    "docs/milestones/03-batched-array-streaming-operations.md"
  ]

  @acceptance_records [
    "docs/milestones/01-native-foundation-acceptance.md",
    "docs/milestones/02-projection-api-acceptance.md",
    "docs/milestones/03-batched-array-streaming-acceptance.md",
    "docs/milestones/05-compatible-decode-api-acceptance.md"
  ]

  @release_guides [
    "docs/releases/preflight.md",
    "docs/releases/provenance.md",
    "docs/releases/publishing.md",
    "docs/releases/recovery.md",
    "docs/releases/installation.md",
    "docs/releases/support.md",
    "docs/releases/ci-policy.md"
  ]

  def project do
    [
      app: :simd_json,
      name: "SimdJson",
      version: @version,
      elixir: "~> 1.18.4",
      start_permanent: Mix.env() == :prod,
      description: "An ownership-safe Elixir NIF wrapper for simdjson",
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
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zigler, "== 0.16.0", runtime: false},
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
        "native/README.md",
        "native/manifest.exs",
        "native/qualification/milestone_1.exs",
        "native/include",
        "native/src",
        "native/symbols",
        "native/vendor",
        "native/zig",
        "docs",
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
           filename: "third-party-notices", title: "Third-Party Notices"},
          {"docs/milestones/README.md", filename: "milestones", title: "Milestone Roadmap"}
        ] ++
          List.delete(@milestone_guides, "docs/milestones/README.md") ++
          @operations_guides ++ @acceptance_records ++ @release_guides,
      groups_for_extras: [
        "Milestone guides": @milestone_guides,
        "Operations guides": @operations_guides,
        "Acceptance records": @acceptance_records,
        "Release notes": ["CHANGELOG.md"],
        Security: ["SECURITY.md"],
        Contributing: ["CONTRIBUTING.md"],
        "Release policies": @release_guides
      ]
    ]
  end
end
