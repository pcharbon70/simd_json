defmodule SimdJson.ReleaseToolingContractTest do
  use ExUnit.Case, async: true

  @preflight "scripts/release/preflight.sh"
  @preflight_guide "docs/releases/preflight.md"
  @phase ".spec/planning/milestone_06_publication_readiness/phase-04-release-tooling-provenance-and-recovery.md"

  # covers: simd_json.release.read_only_preflight simd_json.release.candidate_preflight
  test "defines a credential-free read-only release preflight" do
    script = File.read!(@preflight)
    guide = File.read!(@preflight_guide)

    assert script =~ "release preflight refuses to run while HEX_API_KEY is set"
    assert script =~ "git symbolic-ref --quiet --short HEAD"
    assert script =~ "git status --porcelain=v1 --untracked-files=all"
    assert script =~ "git ls-remote --heads origin refs/heads/main"
    assert script =~ "git ls-remote --exit-code --tags origin"
    assert script =~ "https://hex.pm/api/packages/simd_json/releases/"
    assert script =~ "mix format --check-formatted"
    assert script =~ "mix docs --warnings-as-errors"
    assert script =~ "verify_package_documentation.sh"
    assert script =~ "mix simd_json.verify_qualification"
    assert script =~ "mix spec.check --no-run-commands"
    assert script =~ "preflight.env"
    assert script =~ "SHA256SUMS"

    refute script =~ "mix hex.publish --yes"
    refute script =~ "git tag "
    refute script =~ "git push "
    refute script =~ "gh release create"

    assert guide =~ "clean `main` checkout"
    assert guide =~ ~r/deliberately does\s+not fetch/
    assert guide =~ "unset HEX_API_KEY"
    assert guide =~ "never reads Hex ownership or key data"
    assert guide =~ "Full release-candidate qualification remains a separate Phase 5 gate"

    assert {_output, 0} =
             System.cmd("bash", ["-n", @preflight], stderr_to_stdout: true)
  end

  # covers: simd_json.release.read_only_preflight
  test "rejects ambiguous identity and inherited publication credentials before IO" do
    {usage, 64} = System.cmd("/bin/bash", [@preflight], stderr_to_stdout: true)
    assert usage =~ "usage: preflight.sh VERSION TAG"

    {invalid_version, 64} =
      System.cmd("/bin/bash", [@preflight, "01.0.0", "v01.0.0"], stderr_to_stdout: true)

    assert invalid_version =~ "not a plain semantic version"

    {credential_guard, 64} =
      System.cmd("/bin/bash", [@preflight, "0.1.0", "v0.1.0"],
        env: [{"HEX_API_KEY", "must-not-be-printed"}],
        stderr_to_stdout: true
      )

    assert credential_guard =~ "refuses to run while HEX_API_KEY is set"
    refute credential_guard =~ "must-not-be-printed"
  end

  # covers: simd_json.release.read_only_preflight
  test "closes every read-only preflight planning task" do
    phase = File.read!(@phase)
    [_, phase_sections] = String.split(phase, "## 4.1 Section", parts: 2)
    section = phase_sections |> String.split("## 4.2 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 4.1 Section"
  end
end
