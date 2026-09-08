defmodule SimdJson.ReleaseToolingContractTest do
  use ExUnit.Case, async: true

  @preflight "scripts/release/preflight.sh"
  @preflight_guide "docs/releases/preflight.md"
  @provenance_guide "docs/releases/provenance.md"
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

  # covers: simd_json.release.archive_integrity simd_json.release.provenance
  test "binds an exactly reproducible archive to retained provenance" do
    verifier = File.read!("scripts/ci/verify_package_documentation.sh")
    aggregate = File.read!("scripts/ci/qualify_milestone_5.sh")
    inventory = File.read!("scripts/ci/generate_dependency_inventory.exs")
    workflow = File.read!(".github/workflows/ci.yml")
    guide = File.read!(@provenance_guide)

    assert verifier =~ "archive_build_first"
    assert verifier =~ "archive_build_second"
    assert verifier =~ "package-files.normalized.tsv"
    assert verifier =~ "cmp -s"
    assert verifier =~ "repeated_archive_sha256"
    assert verifier =~ "simd_json-0.1.0.tar"
    assert verifier =~ "dependency-licenses.tsv"
    assert verifier =~ "provenance.env"
    assert verifier =~ "qualification_input_sha256"
    assert verifier =~ "archive_reproducible=true"
    assert verifier =~ "nondeterministic_fields=none"
    assert verifier =~ "SHA256SUMS"

    assert inventory =~ "hex_metadata.config"
    assert inventory =~ "Apache-2.0 OR MIT"
    assert inventory =~ "optional"

    assert aggregate =~ "SIMD_JSON_REQUIRE_CLEAN_CANDIDATE=1"
    assert aggregate =~ ~s(${qualification_root}/release-candidate)
    assert workflow =~ "milestone-6-release-qualification-${{ matrix.cache-mode }}-"
    assert workflow =~ "path: _build/qualification"
    assert workflow =~ "retention-days: 30"

    assert guide =~ ~r/both complete archive SHA-256\s+digests to match/
    assert guide =~ "nondeterministic_fields=none"
    assert guide =~ "fixed 30-day"

    assert {_output, 0} =
             System.cmd("bash", ["-n", "scripts/ci/verify_package_documentation.sh"],
               stderr_to_stdout: true
             )
  end

  # covers: simd_json.release.provenance
  test "closes every archive provenance planning task" do
    phase = File.read!(@phase)
    [_, phase_sections] = String.split(phase, "## 4.2 Section", parts: 2)
    section = phase_sections |> String.split("## 4.3 Section", parts: 2) |> hd()

    refute section =~ "- [ ]"
    assert section =~ "- [x] 4.2 Section"
  end
end
