defmodule SimdJson.Phase6ReleaseCandidateContractTest do
  use ExUnit.Case, async: true

  @phase ".spec/planning/milestone_06_publication_readiness/phase-06-release-candidate-qualification-and-go-no-go.md"
  @qualification "scripts/ci/qualify_release_candidate.sh"

  # covers: simd_json.release.green_ci simd_json.release.candidate_preflight
  test "qualifies the exact supported-target candidate and retains bounded proof" do
    script = File.read!(@qualification)
    workflow = File.read!(".github/workflows/ci.yml")

    assert script =~ "Ubuntu 24.04"
    assert script =~ "qualify_milestone_5.sh"
    assert script =~ "independent_native_build_roots=2"
    assert script =~ "archive_build_roots=2"
    assert script =~ "source_revision="
    assert script =~ "source_tree="
    assert script =~ "publication_authorized=false"
    assert script =~ "xargs -0 sha256sum >SHA256SUMS"
    assert workflow =~ "qualify_release_candidate.sh"
    assert workflow =~ "cache-mode: [cold, restored]"

    refute script =~ "mix hex.publish"
    refute script =~ "git tag "
    refute script =~ "gh release create"

    assert {_output, 0} =
             System.cmd("bash", ["-n", @qualification], stderr_to_stdout: true)
  end

  test "closes supported-target clean qualification" do
    phase = File.read!(@phase)
    [_, rest] = String.split(phase, "## 6.1 Section", parts: 2)
    section = rest |> String.split("## 6.2 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 6.1 Section"
  end
end
