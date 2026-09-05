defmodule SimdJson.ReleaseContractTest do
  use ExUnit.Case, async: true

  @decision ".spec/decisions/0018-public-hex-release-contract.md"
  @support "docs/releases/support.md"

  # covers: simd_json.release.public_identity simd_json.release.publication_gate
  test "freezes one public Hex identity and semantic first version" do
    project = Mix.Project.config()
    decision = File.read!(@decision)

    assert project[:app] == :simd_json
    assert project[:version] == "0.1.0"
    assert decision =~ "public `hexpm` repository"
    assert decision =~ "Hex package `simd_json`"
    assert decision =~ "backward-incompatible public changes increment the minor version"
    assert decision =~ "must be rechecked immediately before publication"
  end

  # covers: simd_json.release.project_license simd_json.release.publication_gate
  test "ships the owner-selected MIT grant separately from upstream notices" do
    package = Mix.Project.config() |> Keyword.fetch!(:package)
    files = Keyword.fetch!(package, :files)
    license = File.read!("LICENSE")
    notices = File.read!("THIRD_PARTY_NOTICES.md")

    assert Keyword.fetch!(package, :licenses) == ["MIT"]
    assert "LICENSE" in files
    assert "THIRD_PARTY_NOTICES.md" in files
    assert license =~ "MIT License"
    assert license =~ "Copyright (c) 2026 pcharbon70"
    assert notices =~ "simdjson 4.6.9"
    assert notices =~ "native/vendor/simdjson/LICENSE"
    assert notices =~ "native/vendor/simdjson/LICENSE-MIT"
    assert File.exists?("native/vendor/simdjson/LICENSE")
    assert File.exists?("native/vendor/simdjson/LICENSE-MIT")
  end

  # covers: simd_json.release.qualified_support simd_json.release.publication_gate
  test "publishes only the qualified target and accurate input-memory boundary" do
    support = File.read!(@support)

    assert support =~ "Ubuntu 24.04 LTS"
    assert support =~ "`x86_64-linux-gnu`"
    assert support =~ "OTP 27.3"
    assert support =~ "| Elixir | 1.18.4 |"
    assert support =~ "| Zig | 0.16.0 |"
    assert support =~ "not precompiled NIF binaries"
    assert support =~ ~r/encoded source is\s+therefore already resident in memory/
    assert support =~ "avoid constructing a complete decoded BEAM tree"
    assert support =~ "experimental or unsupported"
  end

  # covers: simd_json.release.publication_gate
  test "does not treat implementation or planning as publication authorization" do
    decision = File.read!(@decision)
    plan = File.read!(".spec/planning/milestone_06_publication_readiness/README.md")

    assert decision =~ "Repository success alone is not authorization to publish"
    assert plan =~ "does not authorize a Hex publication"
    assert plan =~ "Publication requires explicit human approval"
  end
end
